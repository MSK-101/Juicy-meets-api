class Api::V1::Admin::DashboardController < Api::V1::Admin::BaseController
  before_action :authenticate_admin!
  include AdminAuthenticatable

  # GET /api/v1/admin/dashboard
  def index
    dashboard_data = AdminDashboardBlueprint.render_as_hash({})

    render json: {
      success: true,
      data: dashboard_data
    }
  end
end
