postgresql_connection_info = {
  :host     => node['rogue']['networking']['database']['hostname'],
  :port     => node['rogue']['postgresql']['port'],
  :username => node['rogue']['postgresql']['user'],
  :password => node['rogue']['postgresql']['password']
}

geonode_connection_info = node['rogue']['rogue_geonode']['settings']['DATABASES']['default']

execute 'create_postgis_template' do
  not_if "psql -d geonode -c 'SELECT PostGIS_full_version();'", :user => 'postgres'
  user 'postgres'
  command 'psql -c "create extension postgis" -d geonode'
  action :run
end

execute "sync_db" do
  command "#{node['rogue']['geonode']['location']}bin/python #{node['rogue']['rogue_geonode']['location']}/manage.py syncdb --no-initial-data --all"
end

postgresql_database 'add_firestation_view' do
  connection   postgresql_connection_info
  database_name geonode_connection_info[:name]
  sql <<-EOH
  DROP VIEW IF EXISTS firestations;

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

SET search_path = public, pg_catalog;

--
-- Name: firestations; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW firestations AS
 SELECT
    a.name,
    a.address,
    a.city,
    a.state,
    a.zipcode,
    a.geom,
    '#{node['rogue']['networking']['application']['fqdn']}/jurisdictions/fire-stations/' || a.id AS "URL",
    COALESCE(sum(d.firefighter), 0) AS "Total Firefighters",
    COALESCE(sum(d.firefighter_emt), 0) AS "Total Firefighter/EMTS",
    COALESCE(sum(d.firefighter_paramedic), 0) AS "Total Firefighter/Paramedics",
    COALESCE(sum(d.ems_emt), 0) AS "Total EMS only EMTs",
    COALESCE(sum(d.ems_paramedic), 0) AS "Total EMS only Paramedics",
    COALESCE(sum(d.officer), 0) AS "Total Officers",
    COALESCE(sum(d.officer_paramedic), 0) AS "Total Officer/Paramedics",
    COALESCE(sum(d.ems_supervisor), 0) AS "Total EMS Supervisors",
    COALESCE(sum(d.chief_officer), 0) AS "Total Chief Officers"
   FROM (firestation_usgsstructuredata a
     JOIN firestation_firestation b ON (b.usgsstructuredata_ptr_id = a.id)
     LEFT JOIN firestation_staffing d ON (b.usgsstructuredata_ptr_id = d.firestation_id))
  GROUP BY a.id;
  EOH
  action :query
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
  action :nothing
end

execute "extract_fixture_usgs" do
  command "gunzip -c #{Chef::Config['file_cache_path']}/usgs.sql.gz | sudo -u postgres psql -d geonode"
  only_if do File.exists?("#{Chef::Config['file_cache_path']}/usgs.sql.gz") end
  action :nothing
end
