# Admin Seeds
puts "Creating admin users..."

# Create super admin
super_admin = Admin.find_or_create_by(email: 'admin@juicymeets.com') do |admin|
  admin.password = 'admin123'
  admin.password_confirmation = 'admin123'
  admin.role = 'super_admin'
end

puts "Super Admin created: #{super_admin.email}"

# Create regular admin
admin = Admin.find_or_create_by(email: 'moderator@juicymeets.com') do |admin|
  admin.password = 'moderator123'
  admin.password_confirmation = 'moderator123'
  admin.role = 'admin'
end

puts "Admin created: #{admin.email}"

puts "Admin seeds completed!"
