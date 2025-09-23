class CoinDeductionJob < ApplicationJob
  queue_as :default

  # Handle coin deduction in background
  def perform(user_id, deduction_type = :per_swipe)
    case deduction_type
    when :per_swipe
      apply_per_swipe_deduction_async(user_id)
    when :duration
      # Future: handle duration-based deductions
    end
  rescue => e
    Rails.logger.error "CoinDeductionJob failed for user #{user_id}: #{e.message}"
  end

  private

  def apply_per_swipe_deduction_async(user_id)
    user = User.find(user_id)

    return if user.coin_balance <= 0

    per_swipe_rule = DeductionRule.active.per_swipe.first
    return unless per_swipe_rule

    CoinDeductionService.apply_per_swipe_deduction(user_id, per_swipe_rule)
  end
end
