
execute 'create_postgis_template' do
  not_if "psql -d geonode -c 'SELECT PostGIS_full_version();'", :user => 'postgres'
  user 'postgres'
  command 'psql -c "create extension postgis" -d geonode'
  action :run
end

execute "sync_db" do
  command "#{node['rogue']['geonode']['location']}bin/python #{node['rogue']['rogue_geonode']['location']}/manage.py syncdb --no-initial-data --all"
end


file "/etc/cron.d/geoshape_update_data" do
  content "*/30 * * * * rogue /var/lib/geonode/bin/python /var/lib/geonode/rogue_geonode/manage.py update_data > /dev/null\n"
  mode 00755
  action :create_if_missing
end


remote_file "#{Chef::Config['file_cache_path']}/firestation.sql.gz" do
  source "https://s3.amazonaws.com/firecares-share/fixtures/firestation.sql.gz"
  notifies :run, "execute[extract_fixture_usgs]", :immediately
  action :create_if_missing
end


remote_file "#{Chef::Config['file_cache_path']}/usgs.sql.gz" do
  source "https://s3.amazonaws.com/firecares-share/fixtures/usgs.sql.gz"
  notifies :run, "execute[extract_fixture_usgs]", :immediately
  action :create_if_missing
end

execute "extract_fixture_firestation" do
  command "gunzip -c #{Chef::Config['file_cache_path']}/firestation.sql.gz | sudo -u postgres psql -d geonode"
  only_if do File.exists?("#{Chef::Config['file_cache_path']}/firestation.sql.gz") end
end

execute "extract_fixture_usgs" do
  command "gunzip -c #{Chef::Config['file_cache_path']}/usgs.sql.gz | sudo -u postgres psql -d geonode"
  only_if do File.exists?("#{Chef::Config['file_cache_path']}/usgs.sql.gz") end
end