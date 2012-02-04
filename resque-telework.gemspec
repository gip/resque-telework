# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "resque-telework/global"

Gem::Specification.new do |s|
  s.name        = "resque-telework"
  s.version     = Resque::Plugins::Telework::Version
  s.authors     = "Gilles Pirio"
  s.email       = "g36130@gmail.com"
  s.date        = Time.now.strftime('%Y-%m-%d')
  s.homepage    = "https://github.com/gip/resque-telework"
  s.summary     = %q{resque-telework: A Resque plugin aimed at worker management on remote hosts }

  s.add_runtime_dependency 'resque', '~> 1.19.0'
  s.extra_rdoc_files = ["README.md", "MIT-LICENSE"]

  s.files         = `git ls-files`.split("\n")
  s.require_paths = ["lib"]
  s.description = <<description
    TBD
description
end
