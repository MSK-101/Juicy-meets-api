class Api::V1::Admin::DashboardController < Api::V1::Admin::BaseController
  include AdminAuthenticatable
  before_action :authenticate_admin!

  # GET /api/v1/admin/dashboard
  def index
    begin
      dashboard_data = AdminDashboardBlueprint.render_as_hash({})

      render json: {
        success: true,
        data: dashboard_data
      }
    rescue => e

      render json: {
        success: false,
        error: "Failed to load dashboard data",
        data: {
          stats: {
            views: 0,
            revenue: 0,
            activeUsers: 0,
            payingUsers: 0,
            userRetention: 0
          },
          chartData: [],
          recentUsers: [],
          topVideos: []
        }
      }, status: :internal_server_error
    end
  end
end
