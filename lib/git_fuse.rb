require 'rugged'

module GitFuse
  class App
    def initialize(output: STDOUT)
      @output = output
    end

    def run(source_repo, source_branch, target_dir)
      @target_dir = target_dir
      source_sha = fetch(source_repo, source_branch)
      target_sha = build_branch(source_sha)
      repo.references.update(repo.head, target_sha)
      repo.index.read_tree(repo.head.target.tree)
      repo.checkout_head(paths: target_dir, strategy: :recreate_missing)
    end

    attr_reader :target_dir

    private

    Error = Class.new(RuntimeError)

    def fetch(repo_url, branch)
      remote = repo.remotes.create_anonymous(repo_url)
      remote.fetch("refs/heads/#{branch}")
      branch = remote.ls.find { |r| r[:name] == "refs/heads/#{branch}" } or
        raise Error, "no branch '#{branch}' in source repository"
      branch[:oid]
    end

    def build_branch(root_oid)
      commit_map = {head.oid => head.oid}

      walker = Rugged::Walker.new(repo)
      walker.sorting(Rugged::SORT_TOPO | Rugged::SORT_REVERSE)
      walker.push(root_oid)

      walker.each do |commit|
        commit = repo.lookup(commit.oid)

        new_parent_ids = commit.parent_ids.map { |oid| commit_map[oid] }
        new_parent_ids = [head.oid] if new_parent_ids.empty?
        next if !new_parent_ids.all?

        new_commit_id = Rugged::Commit.create(
          repo,
          author: commit.author,
          message: commit.message,
          committer: commit.committer,
          parents: new_parent_ids,
          tree: create_tree_for(commit),
        )
        subject = commit.message[/.*/].sub(/(?<=.{72}).+/, '...')
        @output.puts "added: #{commit.oid[0, 8]} #{commit.time}: #{subject}"
        commit_map[commit.oid] = new_commit_id
      end

      commit_map[root_oid]
    end

    def create_tree_for(commit)
      builder = Rugged::Tree::Builder.new(repo)
      builder << {
        name: target_dir,
        type: :tree,
        oid: commit.tree.oid,
        filemode: 040000,
      }
      head.tree.each do |entry|
        builder << entry
      end
      builder.write
    end

    def repo
      @repo ||= Rugged::Repository.discover('.')
    end

    def head
      @head_tree ||= repo.head.target
    end

    def parse_options(args)
      OptionParser.new do |parser|
        parser.on '--branch BRANCH', "Branch of the source repo to fuse (default: master)"
      end.parse!(args)
    end
  end
end
