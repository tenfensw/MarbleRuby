#!/usr/bin/env ruby
require 'fileutils'

version = ARGV[0] || '2.4.6'
if version.start_with? '-' then
	puts "Usage: ruby #{$0} VERSION"
	exit 1
end
dir = Dir.pwd + '/MarbleRuby' + version
if File.directory? dir then
	FileUtils.rm_rf(dir)
end
FileUtils.mkdir_p(dir)
FileUtils.cp('start-irb.rb', dir + '/marbleruby.rb')
if system('ruby bundle.rb ' + version + ' "' + dir + '"') == false then
	FileUtils.rm_rf(dir)
	exit 1
end
FileUtils.rm_rf(dir)
exit 0
