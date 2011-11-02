# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "wpify/version"

Gem::Specification.new do |s|
  s.name        = "wpify"
  s.version     = Wpify::VERSION
  s.authors     = ["University Communications at UW-Madison"]
  s.email       = ["bshelton2@wisc.edu"]
  s.homepage    = ""
  s.summary     = %q{Wordpress deploy tools, including a capistrano recipe}
  s.description = %q{Wordpress deploy tools, including a Capistrano recipe}

  s.rubyforge_project = "wpify"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  s.add_runtime_dependency "capistrano"
end
