class Api::V1::CoinDeductionRulesController < ApplicationController
  # before_action :authenticate_user!

  def index
    @coin_deduction_rules = CoinDeductionRule.active.ordered

    render json: {
      coin_deduction_rules: @coin_deduction_rules.map do |rule|
        {
          id: rule.id,
          name: rule.name,
          duration_seconds: rule.duration_seconds,
          duration_minutes: rule.duration_minutes,
          coins_deducted: rule.coins_deducted,
          coins_per_minute: rule.coins_per_minute,
          description: rule.description,
          active: rule.active,
          sort_order: rule.sort_order
        }
      end
    }
  end
end
