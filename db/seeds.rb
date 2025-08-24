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
    name: "Bronze",
    price: 10.00,
    coins_count: 200,
    description: "Basic package for new users",
    sort_order: 1
  },
  {
    name: "Silver",
    price: 15.00,
    coins_count: 300,
    description: "Popular choice for regular users",
    sort_order: 2
  },
  {
    name: "Gold",
    price: 25.00,
    coins_count: 400,
    description: "Premium package for power users",
    sort_order: 3
  }
]

coin_packages.each do |package_data|
  CoinPackage.find_or_create_by(name: package_data[:name]) do |package|
    package.assign_attributes(package_data)
  end
end

puts "Created #{CoinPackage.count} coin packages"

# Create sample deduction rules for testing
puts "Creating deduction rules..."
deduction_rules = [
  {
    name: "10 Second Rule",
    threshold_seconds: 10,
    coins: 5,
    active: true
  },
  {
    name: "30 Second Rule",
    threshold_seconds: 30,
    coins: 10,
    active: true
  },
  {
    name: "1 Minute Rule",
    threshold_seconds: 60,
    coins: 15,
    active: true
  },
  {
    name: "2 Minute Rule",
    threshold_seconds: 120,
    coins: 25,
    active: true
  }
]

deduction_rules.each do |rule_data|
  DeductionRule.find_or_create_by(threshold_seconds: rule_data[:threshold_seconds]) do |rule|
    rule.assign_attributes(rule_data)
  end
end

puts "Created #{DeductionRule.count} deduction rules"

# Create test user for development
if Rails.env.development?
  test_user = User.find_or_create_by(email: 'test@example.com') do |user|
    user.password = 'password123'
    user.password_confirmation = 'password123'
    user.confirmed_at = Time.current
    user.role = 'user'
    user.coin_balance = 0
  end

  puts "Test user created: #{test_user.email}"
end

# Load admin seeds
load(Rails.root.join('db', 'seeds', 'admin_seeds.rb'))

puts "Seed data created successfully!"
