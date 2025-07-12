class Api::Admin::CoinDeductionRulesController < ApplicationController
  # before_action :authenticate_user!
  before_action :set_coin_deduction_rule, only: [:show, :update, :destroy]

  def index
    @coin_deduction_rules = CoinDeductionRule.all.order(:sort_order, :duration_seconds)
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
          sort_order: rule.sort_order,
          created_at: rule.created_at,
          updated_at: rule.updated_at
        }
      end
    }
  end

  def show
    render json: {
      coin_deduction_rule: {
        id: @coin_deduction_rule.id,
        name: @coin_deduction_rule.name,
        duration_seconds: @coin_deduction_rule.duration_seconds,
        duration_minutes: @coin_deduction_rule.duration_minutes,
        coins_deducted: @coin_deduction_rule.coins_deducted,
        coins_per_minute: @coin_deduction_rule.coins_per_minute,
        description: @coin_deduction_rule.description,
        active: @coin_deduction_rule.active,
        sort_order: @coin_deduction_rule.sort_order,
        created_at: @coin_deduction_rule.created_at,
        updated_at: @coin_deduction_rule.updated_at
      }
    }
  end

  def create
    @coin_deduction_rule = CoinDeductionRule.new(coin_deduction_rule_params)

    if @coin_deduction_rule.save
      render json: {
        coin_deduction_rule: {
          id: @coin_deduction_rule.id,
          name: @coin_deduction_rule.name,
          duration_seconds: @coin_deduction_rule.duration_seconds,
          duration_minutes: @coin_deduction_rule.duration_minutes,
          coins_deducted: @coin_deduction_rule.coins_deducted,
          coins_per_minute: @coin_deduction_rule.coins_per_minute,
          description: @coin_deduction_rule.description,
          active: @coin_deduction_rule.active,
          sort_order: @coin_deduction_rule.sort_order,
          created_at: @coin_deduction_rule.created_at,
          updated_at: @coin_deduction_rule.updated_at
        }
      }, status: :created
    else
      render json: {
        errors: @coin_deduction_rule.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def update
    if @coin_deduction_rule.update(coin_deduction_rule_params)
      render json: {
        coin_deduction_rule: {
          id: @coin_deduction_rule.id,
          name: @coin_deduction_rule.name,
          duration_seconds: @coin_deduction_rule.duration_seconds,
          duration_minutes: @coin_deduction_rule.duration_minutes,
          coins_deducted: @coin_deduction_rule.coins_deducted,
          coins_per_minute: @coin_deduction_rule.coins_per_minute,
          description: @coin_deduction_rule.description,
          active: @coin_deduction_rule.active,
          sort_order: @coin_deduction_rule.sort_order,
          created_at: @coin_deduction_rule.created_at,
          updated_at: @coin_deduction_rule.updated_at
        }
      }
    else
      render json: {
        errors: @coin_deduction_rule.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    if @coin_deduction_rule.destroy
      render json: { message: 'Coin deduction rule deleted successfully' }
    else
      render json: {
        errors: @coin_deduction_rule.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def set_coin_deduction_rule
    @coin_deduction_rule = CoinDeductionRule.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Coin deduction rule not found' }, status: :not_found
  end

  def coin_deduction_rule_params
    params.require(:coin_deduction_rule).permit(:name, :duration_seconds, :coins_deducted, :description, :active, :sort_order)
  end
end
