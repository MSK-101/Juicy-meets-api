class StaffAssignment < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :pool
  belongs_to :sequence

  # Validations
  validates :user_id, presence: true, uniqueness: true
  validates :pool_id, presence: true
  validates :sequence_id, presence: true
  validates :status, presence: true, inclusion: { in: %w[active inactive] }
  validates :assigned_gender, presence: true, inclusion: { in: %w[M F] }

  # Enums
  enum status: { active: 'active', inactive: 'inactive' }
  enum assigned_gender: { M: 'M', F: 'F' }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :by_pool, ->(pool_id) { where(pool_id: pool_id) }
  scope :by_gender, ->(gender) { where(assigned_gender: gender) }
  scope :online, -> { joins(:user).where(users: { status: [:online, :in_chat] }) }

  # Callbacks
  before_validation :ensure_user_is_staff
  before_create :set_defaults

  # Instance methods
  def is_available?
    active? && user.online? && !user.in_chat?
  end

  def pool_name
    pool.name
  end

  def sequence_name
    sequence.name
  end

  def staff_name
    user.email
  end

  private

  def ensure_user_is_staff
    unless user&.is_staff?
      errors.add(:user, 'must be a staff member')
    end
  end

  def set_defaults
    self.status ||= 'active'
    self.assigned_gender ||= 'M'
  end
end
