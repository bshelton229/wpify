require 'benchmark'
require 'yaml'
require 'capistrano/recipes/deploy/scm'
require 'capistrano/recipes/deploy/strategy'

Capistrano::Configuration.instance(:must_exist).load do

  def _cset(name, *args, &block)
    unless exists?(name)
      set(name, *args, &block)
    end
  end

  # =========================================================================
  # These variables MUST be set in the client capfiles. If they are not set,
  # the deploy will fail with an error.
  # =========================================================================

  _cset(:application) { abort "Please specify the name of your application, set :application, 'foo'" }
  _cset(:repository)  { abort "Please specify the repository that houses your application's code, set :repository, 'foo'" }
  _cset(:deploy_to) { abort "Please specify deploy to location, set :deploy_to, '/home/deploy/app'" }

  # =========================================================================
  # These variables may be set in the client capfile if their default values
  # are not sufficient.
  # =========================================================================

  _cset :scm, :git
  _cset :deploy_via, :remote_cache
  _cset :use_sudo, false

  _cset(:revision)  { source.head }

  _cset :rake, "rake"

  _cset :maintenance_basename, "maintenance"

  # =========================================================================
  # These variables should NOT be changed unless you are very confident in
  # what you are doing. Make sure you understand all the implications of your
  # changes if you do decide to muck with these!
  # =========================================================================

  _cset(:source)            { Capistrano::Deploy::SCM.new(scm, self) }
  _cset(:real_revision)     { source.local.query_revision(revision) { |cmd| with_env("LC_ALL", "C") { run_locally(cmd) } } }

  _cset(:strategy)          { Capistrano::Deploy::Strategy.new(deploy_via, self) }

  # If overriding release name, please also select an appropriate setting for :releases below.
  _cset(:release_name)      { set :deploy_timestamped, true; Time.now.utc.strftime("%Y%m%d%H%M%S") }

  _cset :version_dir,       "releases"
  _cset :shared_dir,        "shared"
  _cset :shared_children,   %w(config)
  _cset :current_dir,       "current"

  _cset(:releases_path)     { File.join(deploy_to, version_dir) }
  _cset(:shared_path)       { File.join(deploy_to, shared_dir) }
  _cset(:current_path)      { File.join(deploy_to, current_dir) }
  _cset(:release_path)      { File.join(releases_path, release_name) }

  _cset(:releases)          { capture("ls -x #{releases_path}", :except => { :no_release => true }).split.sort }
  _cset(:current_release)   { releases.length > 0 ? File.join(releases_path, releases.last) : nil }
  _cset(:previous_release)  { releases.length > 1 ? File.join(releases_path, releases[-2]) : nil }

  _cset(:current_revision)  { capture("cat #{current_path}/REVISION",     :except => { :no_release => true }).chomp }
  _cset(:latest_revision)   { capture("cat #{current_release}/REVISION",  :except => { :no_release => true }).chomp }
  _cset(:previous_revision) { capture("cat #{previous_release}/REVISION", :except => { :no_release => true }).chomp if previous_release }

  _cset(:run_method)        { fetch(:use_sudo, true) ? :sudo : :run }

  # some tasks, like symlink, need to always point at the latest release, but
  # they can also (occassionally) be called standalone. In the standalone case,
  # the timestamped release_path will be inaccurate, since the directory won't
  # actually exist. This variable lets tasks like symlink work either in the
  # standalone case, or during deployment.
  _cset(:latest_release) { exists?(:deploy_timestamped) ? release_path : current_release }

  # Set default run options
  default_run_options[:pty] = true

  # The directories from the release that are linked into wp-content
  _cset :link_dirs,     %w(themes plugins)
  _cset :group_writable, true

  # =========================================================================
  # These are helper methods that will be available to your recipes.
  # =========================================================================

  # Auxiliary helper method for the `deploy:check' task. Lets you set up your
  # own dependencies.
  def depend(location, type, *args)
    deps = fetch(:dependencies, {})
    deps[location] ||= {}
    deps[location][type] ||= []
    deps[location][type] << args
    set :dependencies, deps
  end

  # Temporarily sets an environment variable, yields to a block, and restores
  # the value when it is done.
  def with_env(name, value)
    saved, ENV[name] = ENV[name], value
    yield
  ensure
    ENV[name] = saved
  end

  # logs the command then executes it locally.
  # returns the command output as a string
  def run_locally(cmd)
    logger.trace "executing locally: #{cmd.inspect}" if logger
    output_on_stdout = nil
    elapsed = Benchmark.realtime do
      output_on_stdout = `#{cmd}`
    end
    if $?.to_i > 0 # $? is command exit code (posix style)
      raise Capistrano::LocalArgumentError, "Command #{cmd} returned status code #{$?}"
    end
    logger.trace "command finished in #{(elapsed * 1000).round}ms" if logger
    output_on_stdout
  end


  # If a command is given, this will try to execute the given command, as
  # described below. Otherwise, it will return a string for use in embedding in
  # another command, for executing that command as described below.
  #
  # If :run_method is :sudo (or :use_sudo is true), this executes the given command
  # via +sudo+. Otherwise is uses +run+. If :as is given as a key, it will be
  # passed as the user to sudo as, if using sudo. If the :as key is not given,
  # it will default to whatever the value of the :admin_runner variable is,
  # which (by default) is unset.
  #
  # THUS, if you want to try to run something via sudo, and what to use the
  # root user, you'd just to try_sudo('something'). If you wanted to try_sudo as
  # someone else, you'd just do try_sudo('something', :as => "bob"). If you
  # always wanted sudo to run as a particular user, you could do
  # set(:admin_runner, "bob").
  def try_sudo(*args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    command = args.shift
    raise ArgumentError, "too many arguments" if args.any?

    as = options.fetch(:as, fetch(:admin_runner, nil))
    via = fetch(:run_method, :sudo)
    if command
      invoke_command(command, :via => via, :as => as)
    elsif via == :sudo
      sudo(:as => as)
    else
      ""
    end
  end

  # Same as sudo, but tries sudo with :as set to the value of the :runner
  # variable (which defaults to "app").
  def try_runner(*args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    args << options.merge(:as => fetch(:runner, "app"))
    try_sudo(*args)
  end

  # =========================================================================
  # These are the tasks that are available to help with deploying web apps,
  # and specifically, Rails applications. You can have cap give you a summary
  # of them with `cap -T'.
  # =========================================================================

  namespace :deploy do
    desc <<-DESC
      Deploys your project. This calls both `update' and `restart'. Note that \
      this will generally only work for applications that have already been deployed \
      once. For a "cold" deploy, you'll want to take a look at the `deploy:cold' \
      task, which handles the cold start specifically.
    DESC
    task :default do
      update
    end

    desc <<-DESC
      Prepares one or more servers for deployment. Before you can use any \
      of the Capistrano deployment tasks with your project, you will need to \
      make sure all of your servers have been prepared with `cap deploy:setup'. When \
      you add a new server to your cluster, you can easily run the setup task \
      on just that server by specifying the HOSTS environment variable:

        $ cap HOSTS=new.server.com deploy:setup

      It is safe to run this task on servers that have already been set up; it \
      will not destroy any deployed revisions or data.
    DESC
    task :setup, :except => { :no_release => true } do
      dirs = [deploy_to, releases_path, shared_path]
      dirs += shared_children.map { |d| File.join(shared_path, d) }
      run "#{try_sudo} mkdir -p #{dirs.join(' ')}"
      run "#{try_sudo} chmod g+w #{dirs.join(' ')}" if fetch(:group_writable, true)
      # Install wordpress latest
      run "cd #{deploy_to}; curl -s -O http://wordpress.org/latest.tar.gz; tar zxf latest.tar.gz; rm latest.tar.gz"
      run "chmod -R g+w #{deploy_to}/wordpress" if fetch(:group_writable, true)
    end

    desc <<-DESC
      Copies your project and updates the symlink. It does this in a \
      transaction, so that if either `update_code' or `symlink' fail, all \
      changes made to the remote servers will be rolled back, leaving your \
      system in the same state it was in before `update' was invoked. Usually, \
      you will want to call `deploy' instead of `update', but `update' can be \
      handy if you want to deploy, but not immediately restart your application.
    DESC
    task :update do
      transaction do
        update_code
        symlink
      end
    end

    desc <<-DESC
      Copies your project to the remote servers. This is the first stage \
      of any deployment; moving your updated code and assets to the deployment \
      servers. You will rarely call this task directly, however; instead, you \
      should call the `deploy' task (to do a complete deploy) or the `update' \
      task (if you want to perform the `restart' task separately).

      You will need to make sure you set the :scm variable to the source \
      control software you are using (it defaults to :subversion), and the \
      :deploy_via variable to the strategy you want to use to deploy (it \
      defaults to :checkout).
    DESC
    task :update_code, :except => { :no_release => true } do
      on_rollback { run "rm -rf #{release_path}; true" }
      strategy.deploy!
      finalize_update
    end

    desc <<-DESC
      [internal] Touches up the released code. This is called by update_code \
      after the basic deploy finishes. It assumes a Rails project was deployed, \
      so if you are deploying something else, you may want to override this \
      task with your own environment's requirements.

      This task will make the release group-writable (if the :group_writable \
      variable is set to true, which is the default). It will then set up \
      symlinks to the shared directory for the log, system, and tmp/pids \
      directories, and will lastly touch all assets in public/images, \
      public/stylesheets, and public/javascripts so that the times are \
      consistent (so that asset timestamping works).  This touch process \
      is only carried out if the :normalize_asset_timestamps variable is \
      set to true, which is the default The asset directories can be overridden \
      using the :public_children variable.
    DESC
    task :finalize_update, :except => { :no_release => true } do
      run "chmod -R g+w #{latest_release}" if fetch(:group_writable, true)
    end

    desc <<-DESC
      Updates the symlink to the most recently deployed version. Capistrano works \
      by putting each new release of your application in its own directory. When \
      you deploy a new version, this task's job is to update the `current' symlink \
      to point at the new version. You will rarely need to call this task \
      directly; instead, use the `deploy' task (which performs a complete \
      deploy, including `restart') or the 'update' task (which does everything \
      except `restart').
    DESC
    task :symlink, :except => { :no_release => true } do
      on_rollback do
        if previous_release
          run "rm -f #{current_path}; ln -s #{previous_release} #{current_path}; true"
        else
          logger.important "no previous release to rollback to, rollback of symlink skipped"
        end
      end

      run "rm -f #{current_path} && ln -s #{latest_release} #{current_path}"
      # Link the wordpress stuff to current path
      # wp_links
      wp_copy_content
    end

    desc "Link the wordpress assets into the wordpress serve folder"
    task :wp_links do
      link_dirs.each do |d|
        run <<-EOB
          if [ -d #{current_path}/wordpress/wp-content/#{d}/ ]; then
            for i in `find #{current_path}/wordpress/wp-content/#{d}/ -maxdepth 1 -mindepth 1 -type d`;
              do ln -nfs $i #{deploy_to}/wordpress/wp-content/#{d}/;
            done;
          fi;
        EOB
      end
    end

    desc "Copy content"
    task :wp_copy_content do
      source = "#{current_path}/wordpress/wp-content/"
      dest = "#{deploy_to}/wordpress/wp-content/"
      run "if [ -d #{source} ] && [ -d #{dest} ]; then cp -Rf #{source}* #{dest}; fi"
    end

    desc <<-DESC
      Copy files to the currently deployed version. This is useful for updating \
      files piecemeal, such as when you need to quickly deploy only a single \
      file. Some files, such as updated templates, images, or stylesheets, \
      might not require a full deploy, and especially in emergency situations \
      it can be handy to just push the updates to production, quickly.

      To use this task, specify the files and directories you want to copy as a \
      comma-delimited list in the FILES environment variable. All directories \
      will be processed recursively, with all files being pushed to the \
      deployment servers.

        $ cap deploy:upload FILES=templates,controller.rb

      Dir globs are also supported:

        $ cap deploy:upload FILES='config/apache/*.conf'
    DESC
    task :upload, :except => { :no_release => true } do
      files = (ENV["FILES"] || "").split(",").map { |f| Dir[f.strip] }.flatten
      abort "Please specify at least one file or directory to update (via the FILES environment variable)" if files.empty?

      files.each { |file| top.upload(file, File.join(current_path, file)) }
    end

    namespace :rollback do
      desc <<-DESC
        [internal] Points the current symlink at the previous revision.
        This is called by the rollback sequence, and should rarely (if
        ever) need to be called directly.
      DESC
      task :revision, :except => { :no_release => true } do
        if previous_release
          run "rm #{current_path}; ln -s #{previous_release} #{current_path}"
        else
          abort "could not rollback the code because there is no prior release"
        end
      end

      desc <<-DESC
        [internal] Removes the most recently deployed release.
        This is called by the rollback sequence, and should rarely
        (if ever) need to be called directly.
      DESC
      task :cleanup, :except => { :no_release => true } do
        run "if [ `readlink #{current_path}` != #{current_release} ]; then rm -rf #{current_release}; fi"
      end

      desc <<-DESC
        Rolls back to the previously deployed version. The `current' symlink will \
        be updated to point at the previously deployed version, and then the \
        current release will be removed from the servers. You'll generally want \
        to call `rollback' instead, as it performs a `restart' as well.
      DESC
      task :code, :except => { :no_release => true } do
        revision
        cleanup
      end

      desc <<-DESC
        Rolls back to a previous version and restarts. This is handy if you ever \
        discover that you've deployed a lemon; `cap rollback' and you're right \
        back where you were, on the previously deployed version.
      DESC
      task :default do
        revision
        cleanup
      end
    end

    desc <<-DESC
      Clean up old releases. By default, the last 5 releases are kept on each \
      server (though you can change this with the keep_releases variable). All \
      other deployed revisions are removed from the servers. By default, this \
      will use sudo to clean up the old releases, but if sudo is not available \
      for your environment, set the :use_sudo variable to false instead.
    DESC
    task :cleanup, :except => { :no_release => true } do
      count = fetch(:keep_releases, 5).to_i
      if count >= releases.length
        logger.important "no old releases to clean up"
      else
        logger.info "keeping #{count} of #{releases.length} deployed releases"

        directories = (releases - releases.last(count)).map { |release|
          File.join(releases_path, release) }.join(" ")

        try_sudo "rm -rf #{directories}"
      end
    end

    desc <<-DESC
      Test deployment dependencies. Checks things like directory permissions, \
      necessary utilities, and so forth, reporting on the things that appear to \
      be incorrect or missing. This is good for making sure a deploy has a \
      chance of working before you actually run `cap deploy'.

      You can define your own dependencies, as well, using the `depend' method:

        depend :remote, :gem, "tzinfo", ">=0.3.3"
        depend :local, :command, "svn"
        depend :remote, :directory, "/u/depot/files"
    DESC
    task :check, :except => { :no_release => true } do
      dependencies = strategy.check!

      other = fetch(:dependencies, {})
      other.each do |location, types|
        types.each do |type, calls|
          if type == :gem
            dependencies.send(location).command(fetch(:gem_command, "gem")).or("`gem' command could not be found. Try setting :gem_command")
          end

          calls.each do |args|
            dependencies.send(location).send(type, *args)
          end
        end
      end

      if dependencies.pass?
        puts "You appear to have all necessary dependencies installed"
      else
        puts "The following dependencies failed. Please check them and try again:"
        dependencies.reject { |d| d.pass? }.each do |d|
          puts "--> #{d.message}"
        end
        abort
      end
    end

    namespace :pending do
      desc <<-DESC
        Displays the `diff' since your last deploy. This is useful if you want \
        to examine what changes are about to be deployed. Note that this might \
        not be supported on all SCM's.
      DESC
      task :diff, :except => { :no_release => true } do
        system(source.local.diff(current_revision))
      end

      desc <<-DESC
        Displays the commits since your last deploy. This is good for a summary \
        of the changes that have occurred since the last deploy. Note that this \
        might not be supported on all SCM's.
      DESC
      task :default, :except => { :no_release => true } do
        from = source.next_revision(current_revision)
        system(source.local.log(from))
      end
    end

    namespace :web do
      desc <<-DESC
        Present a maintenance page to visitors. Disables your application's web \
        interface by writing a "#{maintenance_basename}.html" file to each web server. The \
        servers must be configured to detect the presence of this file, and if \
        it is present, always display it instead of performing the request.

        By default, the maintenance page will just say the site is down for \
        "maintenance", and will be back "shortly", but you can customize the \
        page by specifying the REASON and UNTIL environment variables:

          $ cap deploy:web:disable \\
                REASON="hardware upgrade" \\
                UNTIL="12pm Central Time"

        Further customization will require that you write your own task.
      DESC
      task :disable, :roles => :web, :except => { :no_release => true } do
        require 'erb'
        on_rollback { run "rm #{shared_path}/system/#{maintenance_basename}.html" }

        warn <<-EOHTACCESS

          # Please add something like this to your site's htaccess to redirect users to the maintenance page.
          # More Info: http://www.shiftcommathree.com/articles/make-your-rails-maintenance-page-respond-with-a-503

          ErrorDocument 503 /system/#{maintenance_basename}.html
          RewriteEngine On
          RewriteCond %{REQUEST_URI} !\.(css|gif|jpg|png)$
          RewriteCond %{DOCUMENT_ROOT}/system/#{maintenance_basename}.html -f
          RewriteCond %{SCRIPT_FILENAME} !#{maintenance_basename}.html
          RewriteRule ^.*$  -  [redirect=503,last]
        EOHTACCESS

        reason = ENV['REASON']
        deadline = ENV['UNTIL']

        template = File.read(File.join(File.dirname(__FILE__), "templates", "maintenance.rhtml"))
        result = ERB.new(template).result(binding)

        put result, "#{shared_path}/system/#{maintenance_basename}.html", :mode => 0644
      end

      desc <<-DESC
        Makes the application web-accessible again. Removes the \
        "#{maintenance_basename}.html" page generated by deploy:web:disable, which (if your \
        web servers are configured correctly) will make your application \
        web-accessible again.
      DESC
      task :enable, :roles => :web, :except => { :no_release => true } do
        run "rm #{shared_path}/system/#{maintenance_basename}.html"
      end
    end
  end

  # Wpify commands
  namespace :wpify do
    # Get Version Helper
    def get_version(opts = {:remote => false})
      dir = opts[:remote] ? deploy_to : Dir.getwd
      command = "php -r 'include(\"#{dir}/wordpress/wp-includes/version.php\"); print trim(\$wp_version);'"
      opts[:remote] ? capture(command) : run_locally(command)
    end

    # Remote tasks
    namespace :remote do
      desc "Display the version of Wordpress installed on the first server"
      task :wp_version do
        wp_version = get_version(:remote => true)
        logger.important "Remote WP version: #{wp_version}"
      end
    end

    # Local tasks
    namespace :local do
      desc "Display the version of Wordpress installed locally"
      task :wp_version do
        wp_version = get_version
        logger.important "Local WP version: #{wp_version}"
      end

      desc "Download the remote wp-config.php file"
      task :get_remote_config do
        server = find_servers(:roles => :app, :except => { :no_release => true }).first
        local_config_file = "#{Dir.getwd}/wordpress/wp-config.php"
        if not File.exist? local_config_file
          run_locally "scp #{user}@#{server.host}:#{deploy_to}/wordpress/wp-config.php #{local_config_file}"
        else
          logger.important "A local wp-config.php file already exists. Please remove it first."
        end
      end

      desc "Download the wordpress version installed on the server"
      task :download_wp do
        if(wp_version = get_version(:remote => true))
          logger.info "Download wordpress #{wp_version}"
          run_locally("curl -O http://wordpress.org/wordpress-#{wp_version}.tar.gz")
        end
      end

      desc "Get remote uploads"
      task :get_uploads do
        server = find_servers(:roles => :app, :except => { :no_release => true }).first
        logger.info "Getting uploads from #{server.host}"
        run_locally("rsync -avz #{user}@#{server.host}:#{deploy_to}/wordpress/wp-content/uploads/ #{Dir.getwd}/wordpress/wp-content/uploads/")
      end

      desc "Locally install the Wordpress version installed on the server."
      task :install_wp do
        if(wp_version = get_version(:remote => true))
          logger.info "Downloading wordpress #{wp_version}"
          run_locally("curl -o wp.tar.gz http://wordpress.org/wordpress-#{wp_version}.tar.gz")
          logger.info "Extracting wordpress #{wp_version}"
          run_locally("tar zxf wp.tar.gz; rm wp.tar.gz")
        end
      end

      desc "Rsync remote plugins that aren't tracked in revision control"
      task :sync_untracked_plugins do
        get_remote_tracked = capture "ls -1A #{current_path}/wordpress/wp-content/plugins"
        tracked = get_remote_tracked.split("\n")
        exclude_string = String.new
        tracked.each do |t|
          t.strip!
          exclude_string << " --exclude '#{t}'"
        end
        server = find_servers(:roles => :app, :except => { :no_release => true }).first
        command = "rsync -avz#{exclude_string} #{user}@#{server.host}:#{deploy_to}/wordpress/wp-content/plugins/ #{Dir.getwd}/wordpress/wp-content/plugins/"
        run_locally command
      end

      desc <<-DESC
        Install wordpress locally based on the remote version. \
        Sync untracked plugins from the remote servers to the local machine \
        server. Sync uploads from the remote server to the local machine.
      DESC
      task :bootstrap do
        # This tasks is a collector for various other tasks
        install_wp
        sync_untracked_plugins
        get_uploads
        get_remote_config
      end
    end

    # Tasks that perform local and remote operations
    # desc "Pull and pushes wp-content/uploads files (2-way operation)"
    # task :sync_uploads do
    #   servers = find_servers(:roles => :app, :except => { :no_release => true })
    #   logger.info "Syncing uploads from #{servers.first.host}"
    #   run_locally("rsync -avz --update #{user}@#{servers.first.host}:#{deploy_to}/wordpress/wp-content/uploads/ #{Dir.getwd}/wordpress/wp-content/uploads/")
    #   # Push files to each remote server
    #   servers.each do |server|
    #     logger.info "Pushing files to #{server.host}"
    #     run_locally("rsync -avz --update #{Dir.getwd}/wordpress/wp-content/uploads/ #{user}@#{server.host}:#{deploy_to}/wordpress/wp-content/uploads/")
    #   end
    # end
  end
end
