#!/usr/bin/env ruby
# bundle.rb - pack Ruby version into MarbleRuby.app
# Copyright (C) Tim K 2019. Licensed under MIT License.
require 'open-uri'
require 'fileutils'
require 'plist'

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

def load_plist(plist_path)
	$app = Plist.parse_xml(plist_path)
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
	puts "Usage: ruby #{$0} [/path/to/marbleruby.plist]"
	puts "       ruby #{$0} init"
	exit 1
end

if ['proto', 'init'].include? ARGV[0] then
	out = { 'id' => 'com.yourcompany.yourRubyApp',
	 	'name' => 'Your Ruby app',
		'gems' => [ 'dialogbind', 'plist' ],
		'version' => '0.1',
		'ruby' => '2.3.6',
	        'bundle' => 'YourRubyApp.app',
		'main' => 'main.rb',
		'terminal' => true }.to_plist
	File.write(Dir.pwd + '/marbleruby.plist', out)
	exit 0
end

marbleruby_conf = ARGV[0] || Dir.pwd + '/marbleruby.plist'
if not File.exists? marbleruby_conf then
	puts "Error. #{marbleruby_conf} does not exist."
	exit 6
end

begin
	load_plist(marbleruby_conf)
rescue => e
	puts "Cannot load #{marbleruby_conf} due to this exception: #{e.to_s}."
	exit 7
end

if $app == nil then
	puts "Error. $app structure was not declared in #{marbleruby_conf}."
	exit 8
end

version = $app['ruby'] || '2.6.3'
if version.countc('.') < 2 then
	puts "Error. Incorrect version format (#{version}). The correct one would be: major.minor.update."
	puts "Examples: 2.6.3, 2.7.0, 2.4.1"
	exit 2
end

if version.start_with?('1.') && version.start_with?('1.9') == false then
	puts "Error. Ruby 1.8 and older is not supported. Please try optimizing your app for Ruby 1.9 or newer and try again."
	exit 3
end

puts "Will be packing version Ruby #{version}."
app_version = $app['version'] || '0.1'

gems_to_install = [ 'dialogbind' ]
cli_configure = ''
ARGV.shift
script_dir = File.dirname(marbleruby_conf)
output_app = $app['bundle'] || $app['output'] || File.basename(script_dir) + '.app'
entry_point = $app['launcher'] || 'main.rb'
if not File.directory? script_dir then
	puts "No such file or directory - #{script_dir}."
	exit 3
elsif not File.exists? script_dir + '/' + entry_point then
	puts "There is no launcher script with the name #{entry_point} in the folder. The launcher script must be called \"marbleruby.rb\"."
	exit 4
end
ARGV.shift
puts "Output: #{output_app}"

ARGV.each do |arg|
	cli_configure += arg
end

version_short = version[0..2]
url_formed = "https://cache.ruby-lang.org/pub/ruby/#{version_short}/ruby-#{version}.tar.gz"

puts "Fetching Ruby YARV from #{url_formed}, this might actually take a while..."
system("curl", '-kLo', '/tmp/ruby.tgz', url_formed) or raise("curl failed")
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
final_app_cwd =  script_dir + '/macos-bundle-bin/' + output_app
if File.directory? File.dirname(final_app_cwd) then
	FileUtils.rm_rf(final_app_cwd)
end
FileUtils.mkdir_p(File.dirname(final_app_cwd))
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
brand = $app['name'] || 'MarbleRuby for ' + output_app[0..-5]
appid = $app['id'] || 'ru.timkoi.marbleruby'
terminal = $app['terminal'] || true
subst_conf(final_app_cwd + '/Contents/Info.plist', { 'product' => brand, 'id' => appid, 'version' => app_version })
subst_conf(final_app_cwd + '/Contents/MacOS/marbleruby-launcher', { 'gems' => gems_to_install.join(' '), 'entry_script' => entry_point })
context_clilauncher = { 'd' => 'true' }
if terminal then
	context_clilauncher['d'] = 'false'
end
subst_conf(final_app_cwd + '/Contents/MacOS/marbleruby-clilauncher', context_clilauncher)

puts "Copying the source files..."
FileUtils.mkdir_p(final_app_cwd + '/Contents/Resources/src')
Dir.glob(script_dir + '/*').each do |vitem|
	puts "#{vitem}"
	if File.basename(vitem) != 'macos-bundle-bin' then
		FileUtils.cp_r(vitem, final_app_cwd + '/Contents/Resources/src/' + File.basename(vitem))
	end
end

puts "Installing gems..."
final_app_cwd_gem = final_app_cwd + '/Contents/ContainedRuby/bin/gem'
gems_to_install.each do |item|
	if system('"' + final_app_cwd_gem + '" install -N --conservative --minimal-deps --no-prerelease ' + item) == false then
		puts "Warning. #{item} was not installed. Try again later."
	end
end

puts "Finished! Drag your app to /Applications, sign it and test it out!"
exit 0
