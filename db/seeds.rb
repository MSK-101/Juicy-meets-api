# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)

# Create coin packages
puts "Creating coin packages..."
coin_packages = [
  {
    name: "Starter Pack",
    price: 4.99,
    coins_count: 100,
    description: "Perfect for trying out video chat",
    sort_order: 1
  },
  {
    name: "Popular Pack",
    price: 9.99,
    coins_count: 250,
    description: "Most popular choice for regular users",
    sort_order: 2
  },
  {
    name: "Value Pack",
    price: 19.99,
    coins_count: 600,
    description: "Best value for money",
    sort_order: 3
  },
  {
    name: "Premium Pack",
    price: 39.99,
    coins_count: 1500,
    description: "For power users who chat frequently",
    sort_order: 4
  },
  {
    name: "Mega Pack",
    price: 79.99,
    coins_count: 3500,
    description: "Maximum value for heavy users",
    sort_order: 5
  }
]

coin_packages.each do |package_data|
  CoinPackage.find_or_create_by(name: package_data[:name]) do |package|
    package.assign_attributes(package_data)
  end
end

puts "Created #{CoinPackage.count} coin packages"

# Create coin deduction rules
puts "Creating coin deduction rules..."
deduction_rules = [
  {
    name: "Standard Video Call",
    duration_seconds: 60, # 1 minute
    coins_deducted: 10,
    description: "Standard deduction for video calls",
    sort_order: 1
  },
  {
    name: "Premium Video Call",
    duration_seconds: 300, # 5 minutes
    coins_deducted: 50,
    description: "Premium deduction for longer calls",
    sort_order: 2
  }
]

deduction_rules.each do |rule_data|
  CoinDeductionRule.find_or_create_by(name: rule_data[:name]) do |rule|
    rule.assign_attributes(rule_data)
  end
end

puts "Created #{CoinDeductionRule.count} deduction rules"

puts "Seed data created successfully!"
