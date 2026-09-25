Gem::Specification.new do |spec|
  spec.name        = "familyplates-saas"
  spec.version     = "1.0.0"
  spec.authors     = [ "David Spencer" ]
  spec.summary     = "The hosted edition of FamilyPlates"
  spec.description = "Rails engine that bundles with FamilyPlates to run the hosted service: billing, sign-up, support and the operator console."
  spec.license     = "O'Saasy"

  spec.files = Dir.chdir(__dir__) { Dir["{app,config,lib}/**/*", "README.md"] }

  spec.add_dependency "rails", ">= 8.1"
  spec.add_dependency "pay", "~> 11.7"
  spec.add_dependency "stripe", "~> 19.0"
end
