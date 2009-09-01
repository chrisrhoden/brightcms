require 'rubygems'
require 'sinatra'
require 'activerecord'
require 'redcloth'

configure :production do
  $config = {
    :title => "My Website",
    :description => "Just my little home on the internet!",
    :adapter => 'sqlite3',
    :dbfile => "#{Dir.pwd}/db/application.db",
    :template => 'default'
  }
  
  set :views, Proc.new { File.join(root, "templates/#{$config[:template]}")}
end

configure :development do
  $config = {
    :title => "My Website",
    :description => "Just my little home on the internet",
    :adapter => 'sqlite3',
    :dbfile => "#{Dir.pwd}/db/application_dev.db",
    :template => 'default'
  }
  
  set :views, Proc.new { File.join(root, "templates/#{$config[:template]}")}
end

configure :test do
  $config = {
    :title => "My Website",
    :description => "Just my little home on the internet!",
    :adapter => 'sqlite3',
    :dbfile => 'db/application_test.db',
    :template => 'default'
  }
end

ActiveRecord::Base.establish_connection(
  :adapter => $config[:adapter],
  :dbfile => $config[:dbfile]
)

enable :sessions

# This little hack automatically includes everything dropped
# into the lib directory that ends with .rb and does not start
# with a . - Maybe not the best way to go, but this file is
# starting to make me a little crazy...
configure do
  Dir.foreach(File.join(Dir.pwd, 'lib')) do |file|
    if file =~ /\.rb$/ and not file =~ /^\./ 
      require "lib/#{file}"
    end
  end
end

error(404) do
  custom_erb :four_oh_four
end

get '/' do
  @articles = Post.all.reverse
  custom_erb :index
end

get '/article/:id' do
  @article = Post.find(params[:id])
  custom_erb :view_article
end

post '/article/:id/comment' do
  @article = Post.find(params[:id])
  @comment = Comment.new(:username=>params[:name], :body =>params[:body], :time=>Time.now)
  @comment.save
  @article.comments << @comment
  if @article.save
    flash[:notice] = "Your comment has been added!"
  else
    flash[:notice] = "There was an error adding your comment"
  end
  redirect "/article/#{params[:id]}"
end

get '/work' do
  @projects = Project.all
  custom_erb :work
end

get '/contact' do
  custom_erb :contact
end

post '/contact' do
  if((params[:name].empty? || params[:email].empty? || params[:message].empty? || params[:spam].empty?))
    flash[:notice] = "Please fill in required fields!"
  elsif(params[:spam].upcase == "ORANGE")
    @message = Message.new(:name => params[:name],
                           :email => params[:email],
                           :message => params[:message])
    @message.url = params[:url] unless params[:url].empty?
    @message.save
    flash[:notice] = "Thanks for your message! You'll hear back from me shortly!"
  else
   flash[:notice] = "Oranges are NOT #{params[:spam]}"
  end
  redirect '/contact'
end

get '/admin' do
  if(session[:admin])
    custom_erb :admin
  else
    custom_erb :login
  end
end

post '/admin' do
  username = params[:username]
  password = params[:password]
  @user = User.find(:first, :conditions => ["name = ? AND password = ?", username, password])
  if(@user)
    session[:admin] = @user.id
  else
    flash[:notice] = "Incorrect Username/Password Combination!"
  end
  redirect '/admin'
end

get '/logout' do
  session.clear
  flash[:notice] = "You have been logged out!"
  redirect '/'
end

get '/admin/article' do
  @articles = Post.all
  custom_erb :articles
end

delete '/admin/article/:id' do
  @article = Post.find(params[:id])
  if @article.delete
    flash[:notice] = "Article removed!"
  end
  redirect '/admin/article'
end

get '/admin/article/create' do
  custom_erb :new_article
end

get '/admin/article/edit/:id' do
  @article = Post.find(params[:id])
  custom_erb :edit_article
end

put '/admin/article/:id' do
  @article = Post.find(params[:id])
  @article.title = params[:title]
  @article.body = params[:body]
  if @article.save
    flash[:notice] = "Article updated successfully!"
  else
    flash[:notice] = "There was an error updating this article"
  end
  redirect '/admin/article'
end

post '/admin/article' do
  @post = Post.new(:title => params[:title], :body => params[:body], :date => Time.now, :user_id => session[:admin])
  @post.save
  flash[:notice] = "New article added!"
  redirect '/admin/article'
end



get '/new_project' do
  custom_erb :new_project
end

post '/new_project' do
  @project = Project.new(:title => params[:title],
                         :description => params[:description],
                         :project_type => params[:project_type],
                         :thumbnail_image => "images/portfolio/#{params[:thumbnail_image][:filename]}",
                         :full_image => "images/portfolio/#{params[:full_image][:filename]}",
                         :url => params[:url])
                         
  @thumbnail_image = File.new("public/images/portfolio/#{params[:thumbnail_image][:filename]}", 'w')
  @full_image = File.new("public/images/portfolio/#{params[:full_image][:filename]}", 'w')
  @tempfile = params[:thumbnail_image][:tempfile].open
  @tempfile.each do |f|
    @thumbnail_image.print(f)
  end
  @tempfile = params[:full_image][:tempfile].open
  @tempfile.each do |f|
    @full_image.print(f)
  end       
  @project.save
  flash[:notice] = "New project added!"
  redirect '/admin'
end

get '/delete_project/:id' do
  id = params[:id]
  Project.find(:first, :conditions=> "id = #{id}").delete
  flash[:notice] = "Project deleted!"
  redirect '/admin'
end

get '/edit_project/:id' do
  id = params[:id]
  @project = Project.find(:first, :conditions=> "id = #{id}")
  custom_erb :edit_project
end

post '/edit_project' do
  id = params[:id]
  @project = Project.find(:first, :conditions=> "id = #{id}")
  @project.title = params[:title] unless params[:title].empty?
  @project.description = params[:description] unless params[:description].empty?
  @project.project_type = params[:project_type]
  @project.url = params[:url] unless[:url].empty?
  @project.save
  flash[:notice] = "Project Updated!"
  redirect '/admin'
end

############FILTERS################

before do
  authorize if request.path_info =~ /^\/admin\/./
end


############HELPERS################

helpers do
  def partial(page, options={})
    erb page, options.merge!(:layout => false)
  end

  def flash
    session[:flash] = {} if session[:flash] && session[:flash].class != Hash
    session[:flash] ||= {}
  end

  def custom_erb(*args)
    myerb = erb(*args)
    flash.clear
    myerb
  end
  
  def cycle
    @current ||= %w(even odd)
    @current = [@current.pop] + @current
    @current.first
  end

  def authorize
    redirect '/admin' unless(session[:admin])
  end
end