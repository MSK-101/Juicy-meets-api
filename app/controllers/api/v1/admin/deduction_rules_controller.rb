class Api::V1::Admin::DeductionRulesController < Api::V1::Admin::BaseController
  include AdminAuthenticatable
  before_action :authenticate_admin!

  before_action :set_rule, only: [:show, :update, :destroy]

  # GET /api/v1/admin/deduction_rules
  def index
    rules = DeductionRule.all
    if params[:q].present?
      q = "%#{params[:q]}%"
      rules = rules.where("name ILIKE :q OR CAST(threshold_seconds AS TEXT) ILIKE :q OR CAST(coins AS TEXT) ILIKE :q", q: q)
    end
    if params.key?(:active)
      rules = rules.where(active: ActiveModel::Type::Boolean.new.cast(params[:active]))
    end
    rules = rules.order(:threshold_seconds)
    rules = rules.page(params[:page]).per(params[:per_page] || 20)

    render json: {
      success: true,
      data: {
        deduction_rules: DeductionRuleBlueprint.render_as_hash(rules),
        pagination: {
          page: rules.current_page,
          per_page: rules.limit_value,
          total_pages: rules.total_pages,
          total_count: rules.total_count
        }
      }
    }
  end

  # GET /api/v1/admin/deduction_rules/:id
  def show
    render json: {
      success: true,
      data: {
        deduction_rule: DeductionRuleBlueprint.render_as_hash(@rule)
      }
    }
  end

  # POST /api/v1/admin/deduction_rules
  def create
    rule = DeductionRule.new(rule_params)
    if rule.save
      render json: {
        success: true,
        message: 'Deduction rule created',
        data: { deduction_rule: DeductionRuleBlueprint.render_as_hash(rule) }
      }, status: :created
    else
      render json: { success: false, errors: rule.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/admin/deduction_rules/:id
  def update
    if @rule.update(rule_params)
      render json: {
        success: true,
        message: 'Deduction rule updated',
        data: { deduction_rule: DeductionRuleBlueprint.render_as_hash(@rule) }
      }
    else
      render json: { success: false, errors: @rule.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/admin/deduction_rules/:id
  def destroy
    @rule.destroy
    render json: { success: true, message: 'Deduction rule deleted' }
  end

  private

  def set_rule
    @rule = DeductionRule.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, message: 'Deduction rule not found' }, status: :not_found
  end

  def rule_params
    params.require(:deduction_rule).permit(:name, :threshold_seconds, :coins, :active, :deduction_type)
  end
end
