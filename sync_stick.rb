#!/usr/bin/env ruby

# Copies files of a local folder to a MP3 stick in order.
#
# Many MP3 sticks will play files in order that they have been copied. So
# when anything within a folder changes, all contents of that folder have
# to be copied again. This script will use internal backup and restore to
# avoid copying, which is slow.
#
# Usage:
# ./sync_stick.rb <source folder> [<destination folder>]
#
# Example
# ./sync_stick.rb ~/Stick/ /Volumes/STICK

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
  destination = '/Volumes/STICK'
  unless File.exists?(destination)
    puts "#{destination} is not mounted"
  end
end

class Folder
  SYSTEM_FILES = ['.DS_Store', '.Trashes', '.fseventsd']
  IGNORE = ['..', '.', 'MUSICBMK.BMK', '.Spotlight-V100'] + SYSTEM_FILES
  MD5 = 'md5sum'

  def initialize(path)
    @path = path
    unless File.exists?(path)
      puts "Folder does not exist: #{path}"
      exit(1)
    end
  end

  # Copy entry to .tmp folder.
  def backup(entry)
    unless File.exists?(tmp_path(entry))
      # puts %(backup\t#{path(entry)})
      FileUtils.mv(path(entry), tmp_path(''))
    end
  end

  def checksum
    @checksum ||= begin
      sums = files.map { |f| File.size(path(f)) }
      sums += files
      sums += folders
      Digest::MD5.hexdigest(sums.join.unicode_normalize)
    end
  end

  def delete(path)
    begin
      FileUtils.rm_r(path)
    rescue Errno::ENOENT
    end
  end

  def delete_tmp
    if File.exists?(tmp_path)
      delete(tmp_path)
    end
  end

  def entries
    @entries ||= (Dir.entries(path) - IGNORE).sort_by { |f| f.downcase }
  end

  def folders
    @folders ||= entries.select { |f| File.directory?(path(f)) }
  end

  def files
    @files ||= entries - folders
  end

  def path(name = nil)
    n = @path
    n += "/#{name}" if name
    n
  end

  def delete_system_files
    SYSTEM_FILES.each do |file|
      file_path = path(file)
      if File.exists?(file_path)
        begin
          if size(file_path) > 0
            delete(file_path)
          end
        rescue => e
          %x(sudo rm -rf #{file_path})
        end
      end
    end
  end

  def restore(entry, destination)
    _path = tmp_path(entry)
    if File.exists?(_path) || Dir[_path].any?
      entries = Dir[_path].any? ? Dir[_path] : [_path]
      entries.each do |f|
        name = File.basename(f)
        destination_f = "#{destination}/#{name}"
        if File.exists?(destination_f)
          FileUtils.rm_r(destination_f)
        end
        # puts "restore\t#{f}"
        FileUtils.mv(f, "#{destination}")
      end
      FileUtils.rm_r(_path) if File.exists?(_path)
      true
    end
  end

  def same_size?(source, destination)
    File.size(source) == File.size(destination)
  end

  # Returns size of path in GB.
  def size(_path = path)
    bytes = %x(du -sk #{path})[/^\d+/]
    gb(bytes)
  end

  # Returns disk space of path in GB.
  def space
    bytes = %x(df -k #{path})[/^\/[^\s]+\s+(\d+)/, 1]
    gb(bytes)
  end

  # Syncs target recursively.
  # All files have to be deleted and re-created on stick once
  # anything changes within a folder because the stick sorts items
  # by creation date.
  def sync(target)
    # puts "sync\t#{target}"
    target_folder = Folder.new(target)

    # Work of folder if checksum is different.
    if checksum != target_folder.checksum

      # Backup all entries first.
      target_folder.entries.each do |f|
        next if f['.tmp']
        target_folder.backup(f)
      end
      entries.each do |f|
        source = path(f)
        destination = target_folder.path(f)
        if File.directory?(source)
          unless File.exists?(destination)
            puts "mkdir\t#{destination}"
            FileUtils.mkdir(destination)
          end

          # Restore contents after directory has been created.
          target_folder.restore("#{f}/*", destination)
        else
          restored = target_folder.restore(f, destination)

          # Delete file if size does not match source.
          if restored && !target_folder.same_size?(source, destination)
            puts "delete\t#{destination}"
            target_folder.delete(destination)
          end

          unless File.exists?(destination)
            puts "copy\t#{destination}"
            FileUtils.cp(source, destination)
          end
        end
      end
    end

    # Work on subfolders.
    folders.each do |f|
      Folder.new(path(f)).sync(target_folder.path(f))
    end

    # Delete tmp folder at last.
    target_folder.delete_tmp
  end

  def tmp_path(name = nil)
    @tmp_path ||= begin
      _path = path('.tmp')
      File.exists?(_path) || FileUtils.mkdir(_path)
      _path
    end
    name ? "#{@tmp_path}/#{name}" : @tmp_path
  end

  private

  def gb(bytes)
    (bytes.to_f/1024/1024).round(2)
  end
end

source_folder = Folder.new(source)
destination_folder = Folder.new(destination)
destination_folder.delete_system_files

source_size = source_folder.size
destination_space = destination_folder.space

if source_size > destination_space
  puts "Source size (#{source_size} GB) exceeds destination space (#{destination_space} GB)"
else
  source_folder.sync(destination)
end
