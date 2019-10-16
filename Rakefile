require 'json'
require 'yaml'

require 'bundler/setup'

require_relative 'lib/scraper'

task :default => :scrape

task :scrape => 'data/courses.json' do
  scraper = Scraper.new(courses_path: 'data/courses.json', durations_path: 'data/durations.json')
  scraper.run
end

file_create 'data/courses.json' => 'data/courses.yaml' do |t|
  courses = YAML.load_file(t.prerequisites.first)
  File.write(t.name, JSON.pretty_generate(courses))
end
