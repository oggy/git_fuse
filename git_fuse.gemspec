# -*- encoding: utf-8 -*-
$:.unshift File.expand_path('lib', File.dirname(__FILE__))
require 'git_fuse/version'

Gem::Specification.new do |gem|
  gem.name          = 'git_fuse'
  gem.version       = GitFuse::VERSION
  gem.authors       = ['George Ogata']
  gem.email         = ['george.ogata@gmail.com']
  gem.summary       = "Git command to fuse two repos, preserving full history"
  gem.homepage      = 'http://github.com/oggy/git_fuse'

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")

  gem.add_runtime_dependency 'rugged', '~> 0.24.0'
end
