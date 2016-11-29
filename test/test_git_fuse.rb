ROOT = File.expand_path('..', File.dirname(__FILE__))
$:.unshift "#{ROOT}/lib"

require 'minitest/spec'
require 'minitest/autorun'

require 'git_fuse'

require 'fileutils'
require 'open3'
require 'shellwords'

if !File.respond_to?(:write)
  def File.write(path, content)
    open(path, 'w') { |f| f.write(content) }
  end
end

describe GitFuse do
  def setup
    FileUtils.rm_rf(tmpdir)
    FileUtils.mkdir_p(tmpdir)
  end

  def teardown
    FileUtils.rm_rf(tmpdir)
  end

  let(:tmpdir) { "#{ROOT}/spec/tmp" }
  let(:repo) { Rugged::Repository.new('.') }
  let(:app) { GitFuse::App.new(output: StringIO.new) }

  def make_repo(name)
    sh 'git', 'init', "#{tmpdir}/#{name}"
    Dir.chdir "#{tmpdir}/#{name}" do
      File.write(name, name)
      sh 'git', 'add', name
      sh 'git', 'commit', '-m', name, name
      yield if block_given?
    end
  end

  def graph(from: repo.head.target)
    {from.message.chomp => from.parents.flat_map { |p| graph(from: p).to_a }.to_h}
  end

  def sh(*command, fail_ok: false)
    stdout, stderr, status = Open3.capture3(*command)
    status.success? || fail_ok or
      raise "command failed (#{status.exitstatus}): #{command.shelljoin}" +
        "\n#{stdout.gsub(/^/, '  ')}\n#{stderr.gsub(/^/, '  ')}",
    stdout
  end

  it "fuses the commit graph of the source:master under the given directory" do
    make_repo 'source' do
      sh 'git', 'checkout', '-b', 'a'
      File.write('file', "a\n")
      sh 'git', 'add', 'file'
      sh 'git', 'commit', '-m', 'add a'

      sh 'git', 'checkout', 'master'
      File.write('file', "b\n")
      sh 'git', 'add', 'file'
      sh 'git', 'commit', '-m', 'add b'

      sh 'git', 'merge', 'a', fail_ok: true
      File.write('file', "a\nb\n")
      sh 'git', 'commit', '-m', 'merged', '-a'
    end

    make_repo 'target' do
      app.run('../source', 'master', 'dir')
      graph.must_equal(
        'merged' => {
          'add a' => {'source' => {'target' => {}}},
          'add b' => {'source' => {'target' => {}}},
        },
      )
    end
  end

  it "updates the index and working directory" do
    make_repo 'source'
    make_repo 'target' do
      app.run('../source', 'master', 'dir')
      # TODO: this diffs index to working dir. how to diff index to head?
      repo.index.diff.size.must_equal 0
      File.read('target').must_equal 'target'
      File.read('dir/source').must_equal 'source'
    end
  end

  it "uses a given source branch" do
    make_repo 'source' do
      sh 'git', 'checkout', '-b', 'a'
      File.write('file', "a\n")
      sh 'git', 'add', 'file'
      sh 'git', 'commit', '-m', 'a'

      sh 'git', 'checkout', '-b', 'b', 'master'
      File.write('file', "b\n")
      sh 'git', 'add', 'file'
      sh 'git', 'commit', '-m', 'b'
    end

    make_repo 'target' do
      app.run('../source', 'a', 'dir')
      graph.must_equal('a' => {'source' => {'target' => {}}})
    end
  end
end
