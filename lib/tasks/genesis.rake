namespace :genesis do
  desc "Generate L2 genesis artifacts"
  task :generate => :environment do
    GenesisGenerator.new.run!
  end
end
