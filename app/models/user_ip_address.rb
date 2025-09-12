class UserIpAddress < ApplicationRecord
  belongs_to :user

  validates :ip_address, presence: true
  validates :user_id, uniqueness: { scope: :ip_address }

  # Check if this IP has already been used for free coins
  def self.ip_used_for_free_coins?(ip_address)
    exists?(ip_address: ip_address)
  end
end

