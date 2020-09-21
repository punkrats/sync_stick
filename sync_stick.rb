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
  destination = '/Volumes/STICK'
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

  def backup(entry)
    unless File.exists?(tmp_path(entry))
      puts %(backup\t#{path(entry)})
      FileUtils.mv(path(entry), tmp_path(''))
    end
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

  def path(name = nil)
    n = @path
    n += "/#{name}" if name
    n
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
        puts "restore\t#{f}"
        FileUtils.mv(f, "#{destination}")
      end
      FileUtils.rm_r(_path) if File.exists?(_path)
      true
    end
  end

  def rm_tmp
    if File.exists?(tmp_path)
      FileUtils.rm_r(tmp_path)
    end
  end

  # Returns size in GB
  def size
    bytes = %x(du -sk #{path})[/^\d+/]
    gb(bytes)
  end

  def space
    bytes = %x(df -k #{path})[/^\/[^\s]+\s+(\d+)/, 1]
    gb(bytes)
  end

  # All files have to be deleted and re-created on stick once
  # anything changes within a folder because the stick sorts items
  # by creation date!
  def sync(target)
    puts "sync\t#{target}"
    target_folder = Folder.new(target)

    # Work of folder if checksum is different
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
          unless target_folder.restore(f, destination)
            # exit
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

    # Remove tmp folder at last.
    target_folder.rm_tmp
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

folder = Folder.new(source)
source_size = folder.size
destination_space = Folder.new(destination).space
if source_size > destination_space
  puts "Source size (#{source_size} GB) exceeds destination space (#{destination_space} GB)"
else
  folder.sync(destination)
end
