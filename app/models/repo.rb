class Repo < ActiveRecord::Base
  require 'set'
  attr_accessible :owner, :name
  validates_presence_of :name, :owner
  has_many :shas, dependent: :destroy
  has_many :todos, through: :shas
  before_create :update_info

  def self.top
    Repo.
  end

  def update!
    return unless updated? && updatable?
    modify_shas
    update_info
    save
  end

  def todos?
    todos.length > 0
  end


  def shas_with_todos
    shas.select { |sha| sha.todos? }
  end

  # TODO This method will be used when we allow users to submit their own repos.
  # def real?
  #   begin
  #     Github::API.http_get("repos/#{owner}/#{name}")
  #   rescue RestClient::ResourceNotFound
  #     false
  #   end
  # end

  def updated?
    return true if created_at == updated_at
    begin
      Github::API.http_get("repos/#{owner}/#{name}", "If-Modified-Since" => "#{github_updated_at.httpdate}")
    rescue RestClient::NotModified
      false
    end
  end

  def updatable?
    (new_shas - old_shas).length + 100 < Github::API.rate_remaining 
  end

  def update_info
    self.github_created_at = info[:created_at]
    self.github_updated_at = info[:updated_at]
    self.homepage = info[:homepage]
    self.description = info[:description]
    self.language = info[:language]
    self.forks = info[:forks]
    self.stars = info[:watchers]
    self.issues = info[:open_issues]
    self.git_url = info[:git_url]
    self.master_branch = info[:master_branch]
    self.todos_sum = todos.length
  end

  def files
    self.shas.select { |sha| sha.type == "blob" }
  end

  def info
    return @info if @info
    @info = Github::API.json_get("repos/#{owner}/#{name}")
  end

  def tree
    return @tree if @tree
    path = "repos/#{owner}/#{name}/git/trees/#{master_branch}"
    response = Github::API.json_get(path, params: {recursive: true})
    @tree = response[:tree]
  end

  def modify_shas
    destroy_shas
    create_shas
  end

  def current_shas
    return @current_shas if @current_shas
    @current_shas = Set.new
    self.shas.each { |s| current_shas << s[:sha] }
    @current_shas
  end

  def new_shas
    return @new_shas if @new_shas
    @new_shas = Set.new
    tree.each { |s| new_shas << s[:sha] }
    @new_shas
  end

  def old_shas
    return @old_shas if @old_shas
    @old_shas = current_shas & new_shas
  end

  def create_shas
    to_be_created = new_shas - old_shas
    to_be_created.each do |sha_string| 
      tree.each do |tree_sha|
        shas.create(sha: tree_sha[:sha], path: tree_sha[:path], type: tree_sha[:type]) if tree_sha[:sha] == sha_string
      end
    end
  end

  def destroy_shas
    to_be_destroyed = current_shas - old_shas
    to_be_destroyed.each { |sha| sha.destroy }
  end

end
