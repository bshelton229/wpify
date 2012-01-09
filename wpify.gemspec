# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "wpify/version"

Gem::Specification.new do |s|
  s.name        = "wpify"
  s.version     = Wpify::VERSION
  s.authors     = ["Bryan Shelton"]
  s.email       = ["bryan@sheltonopensolutions.com"]
  s.homepage    = "https://github.com/bshelton229/wpify"
  s.summary     = %q{Wordpress deploy tools, including a capistrano recipe}
  s.description = %q{Wordpress deploy tools, including a capistrano recipe. This project is still in early development}

  s.rubyforge_project = "wpify"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  s.add_runtime_dependency "capistrano", ">= 2"
end
