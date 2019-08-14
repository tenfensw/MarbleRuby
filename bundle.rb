#!/usr/bin/env ruby
# bundle.rb - pack Ruby version into MarbleRuby.app
# Copyright (C) Tim K 2019. Licensed under MIT License.
require 'open-uri'
require 'fileutils'

def bash(desc, cmd, message_on_fail=nil)
	puts "#{desc}"
	if system(cmd) == false then
		if message_on_fail == nil then
			return
		end
		puts "Error. #{message_on_fail}."
		exit 5
	end
end

def subst_conf(file, hash_rep)
	if not File.exists? file then
		return false
	end
	ctnt = File.read(file).gsub("\r\n", "\n")
	hash_rep.keys.each do |key|
		ctnt = ctnt.gsub('>' + key.to_s + '<', hash_rep[key].to_s).clone
	end
	File.write(file, ctnt)
	return true
end

class String
	def countc(character)
		count = 0
		self.split('').each do |item|
			if item == character then
				count += 1
			end
		end
		return count
	end
end

if ARGV.length < 1 || ARGV.include?('--help') then
	puts "Usage: ruby #{$0} VERSION SCRIPT_DIR [--gems=gem1,gem2,etc] [OTHER CONFIGURE OPTIONS] "
	puts "Example: ruby #{$0} 2.6.3"
	exit 1
end

version = ARGV[0] || '2.6.3'
if version.countc('.') < 2 then
	puts "Error. Incorrect version format (#{version}). The correct one would be: major.minor.update."
	puts "Examples: 2.6.3, 2.7.0, 2.4.1"
	exit 2
end

if version.start_with?('1.') && version.start_with?('1.9') == false then
	puts "Error. Ruby 1.8 and older is not supported. Please try optimizing your app for Ruby 1.9 or newer and try again."
	exit 3
end

puts "Will be packing version #{version}."

gems_to_install = [ 'dialogbind' ]
cli_configure = ''
ARGV.shift
script_dir = ARGV[0] || Dir.pwd
output_app = ENV['MARBLERUBY_TARGET'] || File.basename(script_dir) + '.app'
if not File.directory? script_dir then
	puts "No such file or directory - #{script_dir}."
	exit 3
elsif not File.exists? script_dir + '/marbleruby.rb' then
	puts "There is no launcher script in the folder. The launcher script must be called \"marbleruby.rb\"."
	exit 4
end
ARGV.shift
puts "Output: #{output_app}"

ARGV.each do |arg|
	if arg.downcase.start_with? '-gems=' then
		gems_to_install = gems_to_install + arg.split('=')[-1].to_s.split(',')
	else
		cli_configure += arg
	end
end

version_short = version[0..2]
url_formed = "https://cache.ruby-lang.org/pub/ruby/#{version_short}/ruby-#{version}.tar.gz"

puts "Fetching Ruby YARV from #{url_formed}, this might actually take a while..."
url_opened = open(url_formed, 'rb')
out_file = open('/tmp/ruby.tgz', 'wb')
out_file.write(url_opened.read)
out_file.close
url_opened.close
skeleton_path = File.dirname(File.absolute_path($0)) + '/app_template'

puts "Finished! Unpacking..." 
out_build = '/tmp/rubybuild-' + rand(999999).to_s
if File.directory? out_build then
	FileUtils.rm_rf(out_build)
end
FileUtils.mkdir_p(out_build)
bash('Started bsdtar, target = ' + out_build, 'bsdtar --strip-components=1 -C ' + out_build + ' -xzf /tmp/ruby.tgz', 'Failed to unpack Ruby source code into ' + out_build)
#configure_line = 'CFLAGS="-mmacosx-version-min=10.9 -std=c99" CXXFLAGS="-mmacosx-version-min=10.9 -std=c++0x" LIBS="-mmacosx-version-min=10.9"'
configure_line = 'sh'
app_path_rb = '/Applications/' + output_app + '/Contents'
site_rb = app_path_rb + '/Site'
configure_line += ' ./configure --prefix="' + app_path_rb + '/ContainedRuby" '
configure_line += '--with-sitearchhdrdir="' + site_rb + '/Headers/macos64" '
configure_line += '--with-sitehdrdir="' + site_rb + '/Headers" --with-sitedir="' + site_rb + '/Main" '
configure_line += '--with-sitearchdir="' + site_rb + '/macos64" --without-gmp --disable-install-rdoc'
configure_line += ' --disable-install-doc --enable-rpath  --enable-load-relative --disable-werror --disable-option-checking'
configure_line += ' --without-gcc ' + cli_configure + ' --host=x86_64-apple-darwin13.0.0'
configure_line += ' --target=x86_64-apple-darwin13.0.0'
puts "Configure: #{configure_line}"
bash('Started configure', 'cd ' + out_build + ' && ' + configure_line, 'Configure failed.')
bash('Make', 'cd ' + out_build + ' && make -j4 && make install DESTDIR="' + out_build + '/container"', 'Make failed.')
final_app_cwd =  Dir.pwd + '/' + output_app
FileUtils.cp_r(skeleton_path, final_app_cwd)
Dir.glob(out_build + '/container/Applications/' + output_app + '/Contents/*').each do |item|
	if File.directory? item then
		puts "#{item}"
		FileUtils.cp_r(item, final_app_cwd + '/Contents/' + File.basename(item))
		FileUtils.rm_rf(item)
	end
end

puts "Removing build directory..."
FileUtils.rm_rf(out_build)

puts "Reconfigring #{output_app}..."
brand = ENV['MARBLERUBY_APPBRAND'] || 'MarbleRuby for ' + output_app[0..-5]
appid = ENV['MARBLERUBY_APPID'] || 'ru.timkoi.marbleruby'
subst_conf(final_app_cwd + '/Contents/Info.plist', { 'product' => brand, 'id' => appid })
subst_conf(final_app_cwd + '/Contents/MacOS/marbleruby-launcher', { 'gems' => gems_to_install.join(' ') })

puts "Copying the source files..."
FileUtils.cp_r(script_dir, final_app_cwd + '/Contents/Resources/src')

puts "Finished! Drag your app to /Applications, sign it and test it out!"
exit 0
