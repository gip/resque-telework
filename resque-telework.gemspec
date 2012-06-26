# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "resque-telework/global"

Gem::Specification.new do |s|
  s.name        = "resque-telework"
  s.version     = Resque::Plugins::Telework::Version
  s.authors     = "Gilles Pirio"
  s.email       = "gip.github@gmail.com"
  s.date        = Time.now.strftime('%Y-%m-%d')
  s.homepage    = "https://github.com/gip/resque-telework"
  s.summary     = %q{resque-telework: A Resque plugin aimed at controlling Resque workers from the web UI }

  s.add_runtime_dependency 'resque', '~> 1.20.0'
  s.add_runtime_dependency 'sys-cpu', '~> 0.7.0'
  s.extra_rdoc_files = ["README.md", "MIT-LICENSE"]

  s.files         = `git ls-files`.split("\n")
  s.require_paths = ["lib"]
  s.description = <<description
  Telework is a Resque plugin aimed at controlling Resque workers from the web UI. It makes it easy to manage workers on a 
  complex systems that may include several hosts, different queue(s) and an evolving source code that is deployed several times a day. 
  Beyond starting and stopping workers on remote hosts, the plugin makes it easy to switch between code revisions, gives a partial view of 
  each worker's log (stdout and stderr) and maintains a status of each workers.
description
end
