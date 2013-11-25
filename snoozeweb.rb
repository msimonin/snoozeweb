require 'rubygems'
require 'sinatra'
require 'pp'
require 'rest_client'
require 'json'
require 'chartkick'
require 'yaml'

class SnoozeWeb < Sinatra::Base
  set :bind, "0.0.0.0"
  config = YAML.load_file("config.yml")
  
  configure do
    set :public_folder, Proc.new { File.join(root, "static") }
    enable :sessions
    set :bootstrap, "#{config["bootstrap"]["address"]}:#{config["bootstrap"]["port"]}"
    set :imagesRepository, "#{config["imagesRepository"]["address"]}:#{config["imagesRepository"]["port"]}"
    set :stomp,  "#{config["stomp"]["address"]}:#{config["stomp"]["port"]}"
  end

  helpers do
    def username
      session[:identity] ? session[:identity] : 'Hello admin'
    end
  end

  before '/secure/*' do
    if !session[:identity] then
      session[:previous_url] = request.path
      @error = 'Sorry, you need to be logged in to visit ' + request.path
      halt erb(:login_form)
    end
  end

  ##
  #
  # Gets the list of images
  #
  #
  get '/images' do
    display_images
  end

  get '/addVirtualMachines' do
    display_addvirtualmachines
  end

  def display_addvirtualmachines(display = {})
    # get the list of images
    @alert = display[:alert]
    url = "http://#{settings.imagesRepository}/images"
    begin
      @imagesList = RestClient.get url
    rescue
      logger.info "Connection to %s failed." % url
      @imagesList = "{}" 
    end
    @imagesList = JSON.parse(@imagesList)
    @images = @imagesList["images"]
    erb :addvirtualmachines
  end

  def display_images(display = {})
    url = "http://#{settings.imagesRepository}/images"
    begin
      @imagesList = RestClient.get url
    rescue
      logger.info "Connection to %s failed." % url
      @imagesList = "{}" 
    end
    @imagesList = JSON.parse(@imagesList)
    @images = @imagesList["images"]
    @alert = display[:alert]
    erb :images
  end


  ##
  #
  # Delete one image
  #
  #
  post '/images' do
    action = params[:action] 
    imageId = params[:imageId] 
    case(action)
    when "delete"
      url = "http://#{settings.imagesRepository}/images/#{imageId}"
      isDeleted = RestClient.delete url, :content_type => :json, :accept => :json
      if (isDeleted)
        alert = "Image successfully deleted"
      else
        alert = "Unable to delete the image"
      end
    else
    end
    display_images({:alert => alert})
  end

  
  post '/addVirtualMachines' do
    vcpus = params["vcpus"] || 1
    memory = params["memory"].to_i*1000 || 256000
    rx = params["rx"] || 12800
    tx = params["tx"] || 12800
    name = params["name"] || "toto"
    imageId = params["imageId"]
    number = params["number"].to_i
    templates = [] 
    number.times do |n|
      templates << {
        "networkCapacityDemand" =>
        {
          "rxBytes" => rx,
          "txBytes" => tx
        },
        "vcpus"  => vcpus,
        "memory" => memory,
        "name"   => name + "_" + n.to_s,
        "imageId"=> imageId
      }
    end

    template = {"virtualMachineTemplates" => templates }
    puts template.inspect

    url = "http://#{settings.bootstrap}/bootstrap?startVirtualCluster"
    images_str = RestClient.post url, JSON.dump(template), :content_type => :json, :accept => :json
    
    display_addvirtualmachines({:alert => "#{templates.length} virtual machines start requests sent"})

  end

  ##
  #
  # Gets the hierarchy and write result in a file
  #
  #
  get '/hierarchy' do
      contents = JSON.dump({})
      url = "http://#{settings.bootstrap}/bootstrap?getCompleteHierarchy"
      begin
        hierarchy = RestClient.get url
        contents = hierarchy
      rescue
        contents = JSON.dump({})
      end
      File.open("static/vendor/dyn/hierarchy.json", 'w') { |file| file.write(contents) }
      contents
  end

  ##
  #
  # Gets the system info
  #
  #
  #
  get '/system' do
    url = "localhost:4567/hierarchy"
    begin
      hierarchy = RestClient.get url
    rescue
      logger.info "Connection to %s failed." % url
      hierarchy = {}
    end
    puts hierarchy
    erb :system
  end

  ##
  #
  # Gets the events
  #
  get '/events' do
    erb :events
  end

  ##
  #
  # Gets all the groupmanagers
  # 
  # Groupmanagers will be paged with paramers 
  # start and limit
  #
  #
  get '/groupmanagers' do
    if (params.length == 0)
      session[:gmpage] = "{}"
    end
    start = params[:start] || ""
    limit = params[:limit] || "5"
    @parameters = {
      :start => start,
      :limit => limit,
      :numberOfMonitoringEntries => 1,    
    }
    url = "http://#{settings.bootstrap}/bootstrap?getGroupManagerDescriptions"
    body = @parameters.to_json
    begin
      groupmanagers_str = RestClient.post url, body, :content_type => :json, :accept => :json
      @groupmanagers = JSON.parse(groupmanagers_str)
    rescue
      logger.info "Connection to %s failed" % url
      @groupmanagers = {}
    end
    navigation_str = session[:gmpage] || "{}"
    @navigation =  JSON.parse(navigation_str)
    if (@groupmanagers.length >= limit.to_i)
      @first = @groupmanagers.first["id"] 
      @last = @groupmanagers.last["id"]
      @navigation[@last] = @first
      session[:gmpage] = JSON.dump(@navigation) 
    end
    @my_session = session[:gmpage]
    erb :groupmanagers
  end

  post '/groupmanagers/:groupManagerId/reconfiguration' do
    groupManagerId = params["groupManagerId"]
    url = "http://#{settings.bootstrap}/bootstrap?startReconfiguration"
    body = groupManagerId
    begin
      isStarted = RestClient.post url, body, :content_type => :json, :accept => :json
    rescue
      logger.info "Connection to %s failed" % url
    end
    success = "Reconfiguration started"
    error = "Reconfiguration failed"
    if (isStarted)
      @alert = success
    else
      @alert = error
    end
    redirect "/groupmanagers"
  end

  ##
  #
  # Gets the localcontrollers
  #
  # If groupManagerId is empty get all localcontrollers
  # (with memory as database backend you may experience some missing features)
  #
  #
  #
  ["/groupmanagers/:groupManagerId/localcontrollers", "/localcontrollers"].each do |path|
    get path do
      if (params.length == 0)
        session[:lcpage] = "{}"
      end
      start = params[:start] || ""
      limit = params[:limit] || "20"
      groupManagerId = params[:groupManagerId]
      @parameters = {
        :start => start,
        :limit => limit,
        :groupManagerId => groupManagerId
      }
      url = "http://#{settings.bootstrap}/bootstrap?getLocalControllerDescriptions"
      body = @parameters.to_json
      begin
        localcontrollers_str = RestClient.post url, body, :content_type => :json, :accept => :json
        @localcontrollers = JSON.parse(localcontrollers_str)
      rescue
        logger.info "Conection to %s failed" % url
        @localcontrollers = {}
      end
      navigation_str = session[:lcpage] || "{}"
      @navigation =  JSON.parse(navigation_str)
      if (@localcontrollers.length >= limit.to_i)
        @first = @localcontrollers.first["id"] 
        @last = @localcontrollers.last["id"]
        @navigation[@last] = @first
        session[:lcpage] = JSON.dump(@navigation) 
      end
      erb :localcontrollers
    end
  end

  ##
  #
  # Post action on a virtual machine 
  #
  #
  post '/virtualmachines' do
    action = params[:action] 
    virtualMachineLocation = JSON.parse(params[:virtualMachineLocation])
    virtualMachineId = virtualMachineLocation["virtualMachineId"]
    case(action)
    when "destroy"
      url = "http://#{settings.bootstrap}/bootstrap?destroyVirtualMachine"
    when "suspend"
      url = "http://#{settings.bootstrap}/bootstrap?suspendVirtualMachine"
    when "resume"
      url = "http://#{settings.bootstrap}/bootstrap?resumeVirtualMachine"
    when "shutdown"
      url = "http://#{settings.bootstrap}/bootstrap?shutdownVirtualMachine"
    else
      logger.info "Unknown action : %s" % params[:action]
      url = ""
    end
    body="#{virtualMachineId}"
    begin
      response=RestClient.post url, body, :content_type => :json, :accept => :json
    rescue
      logger.info "Unable to fulfill the command %s request" % params[:action]
      response = nil
    end
    error = "Failed to %s virtualmachine %s" % [params[:action], virtualMachineId ]
    success = "%s in progress for %s" % [ params[:action],  virtualMachineId ]
    if (response)
      @alert = success
    else
      @alert = error
    end
    display_virtualmachines(params.merge({:alert => @alert}))
  end

  def display_virtualmachines(display={})
    if (display.length == 0)
      session[:vmpage] = "{}"
    end
    @alert = display[:alert]
    start  = display[:start] || ""
    limit  = display[:limit] || "20"
    action = display[:action] 
    numberOfMonitoringEntries = display[:numberOfMonitoringEntries] || "10"
    localControllerId = display[:localControllerId]
    groupManagerId = display[:groupManagerId]
    @parameters = {
      :start => start,
      :limit => limit,
      :groupManagerId => groupManagerId,
      :localControllerId => localControllerId,
      :numberOfMonitoringEntries => numberOfMonitoringEntries,    
    }
    puts "#### #{settings.bootstrap}"
    url = "http://#{settings.bootstrap}/bootstrap?getVirtualMachineDescriptions"
    body = @parameters.to_json
    begin
      virtualmachines_str= RestClient.post url, body, :content_type => :json, :accept => :json
      @virtualmachineslist = JSON.parse(virtualmachines_str)
      @virtualmachines = @virtualmachineslist["virtualMachines"]
#      @virtualmachines = @virtualmachineslist
    rescue
      @virtualmachines = {}
    end
    navigation_str = session[:vmpage] || "{}"
    @navigation =  JSON.parse(navigation_str)
    if (@virtualmachines.length >= limit.to_i)
      @first = @virtualmachines.first["virtualMachineLocation"]["virtualMachineId"] 
      @last = @virtualmachines.last["virtualMachineLocation"]["virtualMachineId"]
      @navigation[@last] = @first
      session[:vmpage] = JSON.dump(@navigation) 
    end
    erb :virtualmachines
  end

  ##
  #
  # Get all virtualmachine of 
  #  - a groupmanager if present
  #  - or a localcontroller if present
  #
  ["/groupmanagers/:groupManagerId/virtualmachines", "/localcontrollers/:localControllerId/virtualmachines", "/virtualmachines", "/groupmanagers/:groupManagerId/localcontrollers/:localControllerId/virtualmachines"].each do |path|
    get path do
      display_virtualmachines(display = params)
    end
  end


  get '/login/form' do 
    erb :login_form
  end

  post '/login/attempt' do
    session[:identity] = params['username']
    where_user_came_from = session[:previous_url] || '/'
    redirect to where_user_came_from 
  end

  get '/logout' do
    session.delete(:identity)
    erb "<div class='alert alert-message'>Logged out</div>"
  end

end

