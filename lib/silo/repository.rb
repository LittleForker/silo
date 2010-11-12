# This code is free software; you can redistribute it and/or modify it under
# the terms of the new BSD License.
#
# Copyright (c) 2010, Sebastian Staudt

require 'tmpdir'

require 'rubygems'
require 'grit'

module Silo

  # Represents a Silo repository
  #
  # This provides the core features of Silo to initialize a repository and work
  # with it.
  #
  # @author Sebastian Staudt
  # @since 0.1.0
  class Repository

    # @return [Grit::Repo] The Grit object to access the Git repository
    attr_reader :git

    # Creates a new repository instance on the given path
    #
    # @param [Hash] options A hash of options
    # @option options [Boolean] :create (true) Creates the backing Git
    #         repository if it does not already exist
    # @option options [Boolean] :prepare (true) Prepares the backing Git
    #         repository for use with Silo if not already done
    #
    # @raise [Grit::InvalidGitRepositoryError] if the path exists, but is not a
    #        valid Git repository
    # @raise [Grit::NoSuchPathError] if the path does not exist and option
    #        :create is +false+
    # @raise [InvalidRepositoryError] if the path contains another Git
    #        repository that does not contain data managed by Silo.
    def initialize(path, options = {})
      options = {
        :create  => true,
        :prepare => true
      }.merge options

      @path = File.expand_path path

      if File.exist?(path)
        if Dir.new(path).count > 2
          unless File.exist?(File.join(path, 'HEAD')) &&
                 File.stat(File.join(path, 'objects')).directory? &&
                 File.stat(File.join(path, 'refs')).directory?
            raise Grit::InvalidGitRepositoryError.new(path)
          end
        end
        @git = Grit::Repo.new(path, { :is_bare => true })
      else
        if options[:create]
          @git = Grit::Repo.init_bare(path, {}, { :is_bare => true })
        else
          raise Grit::NoSuchPathError.new(path)
        end
      end

      if !prepared? && @git.commit_count > 0
        raise InvalidRepositoryError.new(path)
      end

      prepare if options[:prepare] && !prepared?
    end

    # Stores a file into the repository inside an optional prefix path
    #
    # This adds one commit to the history of the repository including the file
    # or its changes if it already existed.
    #
    # @param [String] path The path of the file to store into the repository
    # @param [String] prefix An optional prefix where the file is stored inside
    #        the repository
    def add(path, prefix = nil)
      dir      = File.dirname path
      file     = File.basename path
      path     = prefix.nil? ? file : File.join(prefix, file)
      in_work_tree dir do
        index = @git.index
        index.read_tree 'HEAD'
        index.add path, IO.read(file)
        commit_msg = "Added file #{file} into '#{prefix || '.'}'"
        index.commit commit_msg, @git.head.commit.sha
      end
    end

    # Run a block of code with +$GIT_WORK_TREE+ set to a specified path
    #
    # This executes a block of code while the environment variable
    # +$GIT_WORK_TREE+ is set to a specified path or alternatively the path of
    # a temporary directory.
    #
    # @param [String, :tmp] path A path or +:tmp+ which will create a temporary
    #        directory that will be removed afterwards
    # @yield [path] The code inside this block will be executed with
    #        +$GIT_WORK_TREE+ set
    # @yieldparam [String] path The absolute path used for +$GIT_WORK_TREE+
    def in_work_tree(path = '.')
      tmp_dir = path == :tmp
      path = tmp_dir ? Dir.mktmpdir : File.expand_path(path)
      Dir.chdir path do
        old_work_tree = ENV['GIT_WORK_TREE']
        ENV['GIT_WORK_TREE'] = path
        yield path
        ENV['GIT_WORK_TREE'] = old_work_tree
        FileUtils.rm_rf path, :secure => true if tmp_dir
      end
    end

    # Prepares the Git repository backing this Silo repository for use with
    # Silo
    #
    # @raise [AlreadyPreparedError] if the repository has been already prepared
    def prepare
      raise AlreadyPreparedError.new(@path) if prepared?
      in_work_tree :tmp do
        FileUtils.touch '.silo'
        @git.add '.silo'
        @git.commit_index 'Enabled Silo for this repository'
      end
    end

    # Return whether the Git repository backing this Silo repository has
    # already been prepared for use with Silo
    #
    # @return The preparation status of the backing Git repository
    def prepared?
      !(@git.tree/'.silo').nil?
    end

  end

end