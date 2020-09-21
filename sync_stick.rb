#!/usr/bin/env ruby

# Copy files to stick in order.
# The sticks will play files on order that they have been copied. So when
# a folder changes, all files have to be copied again.

# Usage:
# ./sync_stick.rb <source folder> [<destination folder>]

# Example
# ./sync_stick.rb ~/Stick/ /Volumes/STICK

# TODO: try to get destination folder on card.

require 'digest'
require 'fileutils'

source = ARGV[0]
destination = ARGV[1]

def usage
	puts './sync_stick.rb <source folder> [<destination folder>]'
	puts './sync_stick.rb ~/Stick/ /Volumes/STICK'
end

unless source && File.exists?(source)
	usage
	exit(1)
end

unless destination
	destination = '/Volumes/STICK/'
	unless File.exists?(destination)
		puts "#{destination} is not mounted"
	end
end

class Folder
	IGNORE = [
		'..', '.', '.DS_Store', '.Spotlight-V100', '.Trashes',
		'.fseventsd', 'MUSICBMK.BMK'
	]
	MD5 = 'md5sum'

	def initialize(path)
		@path = path
	end

	def entries
		# @entries ||= (Dir.entries(path) - IGNORE).sort_by { |f| File.mtime(path(f)) }
		@entries ||= (Dir.entries(path) - IGNORE).sort_by { |f| f.downcase }
	end

	def folders
		@folders ||= entries.select { |f| File.directory?(path(f)) }
	end

	def files
		@files ||= entries - folders
	end

	def delete(entry)
		begin
			print "rm\t#{path(entry)} "
			FileUtils.rm_rf(path(entry))
			puts 'OK'
		rescue Errno::ENOENT
			puts 'FAIL'
		end
	end

	def checksum
		@checksum ||= begin
			sums = files.map { |f| `#{MD5} "#{path(f)}"`[/^\w+/] }
			sums += files
			sums += folders
			Digest::MD5.hexdigest(sums.join)
		end
	end

  def size
    %x(du -s #{path})[/^\d+/].to_i
  end

	# All files have to be deleted and re-created on stick once
  # anything changes within a folder because the stick sorts items
  # by creation date!
	def sync(target)
		target_folder = Folder.new(target)
		if checksum != target_folder.checksum
			# Delete all entries first.
			target_folder.entries.each do |f|
				target_folder.delete(f)
			end
			entries.each do |f|
				source = path(f)
				destination = target_folder.path(f)
				if File.directory?(source)
					puts "mkdir\t#{destination}"
					FileUtils.mkdir(destination)
				else
					puts "copy\t#{destination}"
					FileUtils.cp(source, destination)
				end
			end
		end
		folders.each do |f|
			Folder.new(path(f)).sync(target_folder.path(f))
		end
	end

	def path(name = '')
		"#{@path}/#{name}"
	end
end

folder = Folder.new(source)
if folder.size < Folder.new(destination).size
  folder.sync(destination)
end
