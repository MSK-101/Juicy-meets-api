class Api::V1::Admin::AdminsController < Api::V1::Admin::BaseController
  include AdminAuthenticatable
  before_action :authenticate_admin!

  # GET /api/v1/admin/admins
  def index
    @admins = Admin.all.order(:created_at)

    render json: {
      success: true,
      data: {
        admins: @admins.map { |admin| admin_response(admin) }
      }
    }
  end

  # POST /api/v1/admin/admins
  def create
    @admin = Admin.new(admin_params)
    @admin.role = 'admin' # Default role

    if @admin.save
      render json: {
        success: true,
        message: 'Admin created successfully',
        data: {
          admin: admin_response(@admin)
        }
      }, status: :created
    else
      render json: {
        success: false,
        message: @admin.errors.full_messages.join(', '),
        errors: @admin.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # PUT /api/v1/admin/admins/:id
  def update
    @admin = Admin.find(params[:id])

    if @admin.update(admin_params)
      render json: {
        success: true,
        message: 'Admin updated successfully',
        data: {
          admin: admin_response(@admin)
        }
      }
    else
      render json: {
        success: false,
        message: 'Failed to update admin',
        errors: @admin.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/admin/admins/:id
  def destroy
    @admin = Admin.find(params[:id])

    # Prevent deleting the current admin
    if @admin.id == current_admin.id
      render json: {
        success: false,
        message: 'Cannot delete your own account'
      }, status: :unprocessable_entity
      return
    end

    if @admin.destroy
      render json: {
        success: true,
        message: 'Admin deleted successfully'
      }
    else
      render json: {
        success: false,
        message: 'Failed to delete admin',
        errors: @admin.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def admin_params
    params.require(:admin).permit(:email, :password, :password_confirmation)
  end

  def admin_response(admin)
    {
      id: admin.id,
      email: admin.email,
      role: admin.role,
      display_name: admin.display_name,
      created_at: admin.created_at,
      updated_at: admin.updated_at
    }
  end
end
