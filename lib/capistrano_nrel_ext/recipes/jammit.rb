require "capistrano_nrel_ext/actions/remote_tests"

Capistrano::Configuration.instance(true).load do
  #
  # Varabiles
  #
  set :jammit_apps, []

  #
  # Hooks 
  #
  before "deploy:setup", "deploy:jammit:setup"
  after "deploy:update_code", "deploy:jammit:precache"

  #
  # Dependencies
  #
  depend(:remote, :gem, "jammit", ">= 0.4.4")
  depend(:remote, :command, "jammit")

  #
  # Tasks
  #
  namespace :deploy do
    namespace :jammit do
      task :setup, :except => { :no_release => true } do
        # By default, look inside our root application, as well as any Rails
        # applications that might have their own Jammit configuration.
        jammit_apps = ["."]
        if(exists?(:all_rails_applications))
          rails_apps = all_rails_applications.collect { |application_path, public_path| application_path }
          set(:jammit_apps, jammit_apps + rails_apps)
        end
      end

      desc <<-DESC
        Precache and compress asset files using Jammit.
      DESC
      task :precache, :except => { :no_release => true } do
        jammit_apps.each do |application_path|
          full_application_path = File.join(latest_release, application_path)

          # If this project has javascript to compile first, run those tasks.
          if(remote_rake_task_exists?(full_application_path, "js:compile"))
            env = ""
            if(exists?(:rails_env))
              env = "RAILS_ENV=#{rails_env}"
            end

            run "cd #{full_application_path} && #{env} rake js:compile"
          end

          # Compress things with Jammit.
          if(remote_file_exists?(File.join(full_application_path, "config", "assets.yml")))
            assets_cached_path = File.join(shared_path, application_path, "public", "assets")
            assets_temp_output_path = File.join(shared_path, application_path, "public", "assets-temp-#{release_name}")
            assets_release_path = File.join(full_application_path, "public", "assets")

            # 1. Do a full jammit compression into a temporary folder.
            # 2. Synchronize the new assets into a shared folder that's kept between
            #    deployments.
            #      * This ensures we only update an asset's timestamp when the
            #        file contents change (this keeps timestamp based
            #        cache-busting mechanisms happy).
            #      * This shared folder is not a normal Capistrano
            #        `shared_children` that's symlinked to the live location.
            #        Doing that would send asset changes live too soon and
            #        wouldn't be rolled back if the deploy failed.)
            # 3. Copy the shared assets folder into the directory for the
            #    release being deployed.
            #
            # All of this ensures that timestamps are only updated when needed,
            # and assets don't go live too soon, as well as roll back properly.
            run "cd #{full_application_path} && " +
              "jammit --output #{assets_temp_output_path} && " +
              "rsync -rc --delete-delay #{assets_temp_output_path}/ #{assets_cached_path} && " +
              "rsync -rtc #{assets_cached_path}/ #{assets_release_path} && " +
              "rm -rf #{assets_temp_output_path}"
          end
        end
      end
    end
  end
end
