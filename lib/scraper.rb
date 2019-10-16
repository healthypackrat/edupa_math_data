require 'json'
require 'logger'
require 'nkf'
require 'pathname'

require 'mechanize'

class Scraper
  class Error < StandardError; end

  def initialize(courses_path:, durations_path:, logger: Logger.new($stderr), wait_for: 1.5)
    @courses_path = Pathname.new(courses_path)
    @courses = JSON.parse(@courses_path.read)

    @durations_path = Pathname.new(durations_path)
    @durations = @durations_path.exist? ? JSON.parse(@durations_path.read) : {}

    @logger = logger
    @wait_for = wait_for
  end

  def run
    mech = Mechanize.new

    @courses.each do |course|
      course_url = course.fetch('url')

      wait

      debug "GET: #{course_url}"

      page = mech.get(course_url)

      page.search('.tab').each_with_index do |chapter_tab, chapter_index|
        chapter = course.fetch('chapters').fetch(chapter_index)

        chapter['videos'] ||= []

        videos = chapter['videos']

        chapter_tab.search('a[href*="flvplay"]').each_with_index do |video_link, video_index|
          video = videos[video_index] || {}

          video['position'] = video_index + 1

          handle_video_link(video_link, video)

          videos[video_index] = video

          dump_courses
        end
      end
    end
  end

  private

  def handle_video_link(video_link, video)
    parse_video_link(video_link, video)
    fetch_video_duration(video)
  end

  def parse_video_link(video_link, video)
    return if video.has_key?('video_url')

    flags = []
    # UTF-8で入出力
    flags << '-Ww'
    # 全角記号をASCIIに
    flags << '-Z'
    # 全角空白をASCIIに
    flags << '-Z1'

    video['title'] = NKF.nkf(flags.join(' '), video_link.text).sub(/\s*\(\d+:\d+:\d+\)\z/, '')

    if /flvplay\('([^']+)',(\d+)(?:,(\d+))?/ =~ video_link[:href]
      path = $1
      video['path'] = path
      video['ftype'] = $2
      video['server'] = $3
      video['video_url'] = build_video_url(path)
    else
      raise Error, "invalid href: #{video_link[:href].inspect}"
    end
  end

  def fetch_video_duration(video)
    return if video.has_key?('duration')

    video_url = video.fetch('video_url')

    duration = @durations[video_url]

    if duration
      video['duration'] = duration
    else
      wait

      debug "GET: #{video_url}"

      info = IO.popen(['ffmpeg', '-i', video_url, :err => [:child, :out]], &:read)

      if /Duration: (\d+):(\d+):(\d+\.\d+)/ =~ info
        hours = $1.to_i
        minutes = $2.to_i
        seconds = $3.to_f.ceil

        duration = (hours * 60 * 60) + (minutes * 60) + seconds

        video['duration'] = duration

        @durations[video_url] = duration

        dump_durations
      else
        debug info
        raise Error, 'invalid info'
      end
    end
  end

  def build_video_url(path)
    "http://edupa.info/flv/#{path}.flv"
  end

  def dump_courses
    @courses_path.parent.mkpath
    @courses_path.write(JSON.pretty_generate(@courses))
  end

  def dump_durations
    @durations_path.parent.mkpath
    @durations_path.write(JSON.pretty_generate(@durations))
  end

  def wait
    sleep @wait_for
  end

  def debug(obj)
    @logger&.debug(obj)
  end
end
