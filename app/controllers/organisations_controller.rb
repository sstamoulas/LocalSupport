class OrganisationsController < BaseOrganisationsController
  layout 'two_columns_with_map'
  # GET /organisations/search
  # GET /organisations/search.json
  before_action :authenticate_user!, except: [:search, :index, :show]
  prepend_before_action :set_organisation, only: [:show, :update, :edit]
  prepend_before_action :build_cat_name_ids, only: [:search, :index, :show]
  before_action :add_breadcrumbs

  def search
    @parsed_params = SearchParamsParser.new(params)
    @organisations = Queries::Organisations.search_by_keyword_and_category(
      @parsed_params
    )
    flash.now[:alert] = SEARCH_NOT_FOUND if @organisations.empty?
    @markers = build_map_markers(@organisations)

    render template: 'organisations/index'
  end

  # GET /organisations
  # GET /organisations.json
  def index
    @organisations = Queries::Organisations.order_by_most_recent
    @markers = build_map_markers(@organisations)
  end

  # GET /organisations/1
  # GET /organisations/1.json
  def show
    render template: 'pages/404', status: 404 and return if @organisation.nil?
    organisations = Organisation.where(id: @organisation.id)
    @user_opts = current_user ? get_user_options(@organisation) : {grabbable: true}
    @user_opts[:can_propose_edits] = current_user.present? && !@user_opts[:editable]
    @markers = build_map_markers(organisations)
  end

  # GET /organisations/new
  # GET /organisations/new.json
  def new
    @organisation = Organisation.new
  end

  # GET /organisations/1/edit
  def edit
    organisations = Organisation.where(id: @organisation.id)
    @markers = build_map_markers(organisations)
    return false unless user_can_edit? @organisation
  end

  # POST /organisations
  # POST /organisations.json
  def create
    # model filters for logged in users, but we check here if that user is an superadmin
    # TODO refactor that to model responsibility?
    org_params = OrganisationParams.build params

    unless current_user.try(:superadmin?)
      flash[:notice] = PERMISSION_DENIED
      redirect_to organisations_path and return false
    end
    @organisation = Organisation.new(org_params)
    if @organisation.save
      redirect_to @organisation, notice: 'Organisation was successfully created.'
    else
     render :new
    end
  end

  # PUT /organisations/1
  # PUT /organisations/1.json
  def update
    params[:organisation][:superadmin_email_to_add] = params[:organisation_superadmin_email_to_add] if params[:organisation]
    update_params = OrganisationParams.build params
    return false unless user_can_edit? @organisation
    if @organisation.update_attributes_with_superadmin(update_params)
      redirect_to @organisation, notice: 'Organisation was successfully updated.'
    else
      render action: 'edit'
    end
  end

  # DELETE /organisations/1
  # DELETE /organisations/1.json
  def destroy
    unless current_user.try(:superadmin?)
      flash[:notice] = PERMISSION_DENIED
      redirect_to organisation_path(params[:id]) and return false
    end
    @organisation = Organisation.friendly.find(params[:id])
    @organisation.destroy
    flash[:success] = "Deleted #{@organisation.name}"

    redirect_to organisations_path
  end

  class OrganisationParams
    def self.build params
      params.require(:organisation).permit(
        :superadmin_email_to_add,
        :description,
        :address,
        :publish_address,
        :postcode,
        :email,
        :publish_email,
        :website,
        :publish_phone,
        :donation_info,
        :name,
        :telephone,
        category_ids: []
      )
    end
  end

  private

  def add_breadcrumbs
    org = @organisation
    add_breadcrumb 'All Organisations', :organisations_path
    case action_name
    when 'show'
      add_breadcrumb org.name if org.present?
    when 'edit'
      add_breadcrumb org.name, organisation_path(org) if org.present?
      add_breadcrumb 'Edit Organisation'
    when 'new'
      add_breadcrumb 'New Organisation'
    end
  end

  def build_cat_name_ids
    @cat_name_ids = Category.name_and_id_for_what_who_and_how
  end

  def get_user_options(organisation)
      {
        pending_org_admin: current_user.pending_org_admin?(organisation),
        editable: current_user.can_edit?(organisation),
        deletable: current_user.can_delete?(organisation),
        can_create_volunteer_op: current_user.can_create_volunteer_ops?(organisation),
        grabbable: current_user.can_request_org_admin?(organisation)
      }
  end

  def set_organisation
    @organisation = Organisation.friendly.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    @organisation = nil
  end

  def user_can_edit?(org)
    unless current_user.try(:can_edit?,org)
      flash[:notice] = PERMISSION_DENIED
      redirect_to organisation_path(params[:id]) and return false
    end
    true
  end

  def meta_tag_title
    return super unless @organisation
    @organisation.name
  end

  def meta_tag_description
    return super unless @organisation
    @organisation.description
  end
end
