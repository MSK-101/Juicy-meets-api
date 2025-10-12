class Api::V1::ReportsController < ApplicationController
  before_action :authenticate_user!

  # POST /api/v1/reports
  def create
    result = current_user.report_user(params[:reported_user_id])

    if result[:success]
      render json: { success: true, message: result[:message] }, status: :created
    else
      render json: { success: false, message: result[:message] }, status: :unprocessable_entity
    end
  end

end
