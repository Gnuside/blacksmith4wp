
## INSTALL VIM
class customer::packages {
  package {
  "vim":
    ensure => installed;
  "w3m":
    ensure => installed;
  "rsync":
    ensure => installed;
  "unzip":
    ensure => installed
  }
}

# include mysql
# include php
# include drush

node "vagrant-debian-squeeze.vagrantup.com" {
    $customer_domain = "<% CUSTOMER_DOMAIN %>"
    $customer_wp_theme = "<% CUSTOMER_ID %>-site-wp"
    $customer_wp_path = "/var/www/<% CUSTOMER_ID %>-wp"
    $customer_username = "<% CUSTOMER_ID %>"
    $customer_password = "<% CUSTOMER_ID %>"
    $customer_database = "<% CUSTOMER_ID %>_wp"
    # FIXME: make distinction between db password & wp password

# APT SECTION
# - make sure default keys are in
# - make sure repos are up to date

    class{ "apt":  always_apt_update => true; }
    
    apt::key { 
      "B98321F9": 
        key_source => "http://ftp-master.debian.org/keys/archive-key-6.0.asc";
     "473041FA": 
        key_source => "http://ftp-master.debian.org/keys/archive-key-6.0.asc";
      "F42584E6": 
        key_source => "http://ftp-master.debian.org/keys/archive-key-6.0.asc"
    }

    Apt::Key <| |> -> Exec["apt_update"] 
    Exec["apt_update"] -> Package <| |>

    # globally set exec path
    Exec { path => [ "/bin/", "/sbin/" , "/usr/bin/", "/usr/sbin/" ] }
    
# APACHE SECTION
# - setup 3 virtualhosts
# - enable modules
# - enable virtualhosts
# - enable mod-php

    include apache2

    package { "libapache2-mod-php5": ensure => installed }
    apache2::module { 
    "php5": require => Package["libapache2-mod-php5"];
    "rewrite": require => Package["libapache2-mod-php5"]; 
    "headers": require => Package["libapache2-mod-php5"];
    }

    apache2::vhost {
        "${customer_domain}": documentroot => "${customer_wp_path}";
    }

    apache2::site {
        "${customer_domain}": ensure => 'present';
    }


# PHP5 SECTION
# - install all required php modules
    include php


# MYSQL SECTION
# - setup admin password
# - load database from static files
# - repair database

  include mysql
  mysql::password{"set_password" : password     => "vagrant"}
  mysql::create_database{"${customer_database}": 
    username      => "${customer_username}",
    password      => "${customer_password}",
    root_password => "vagrant",
    require     => Mysql::Password["set_password"]
  }

  ## Load tables in database if none present
  exec {"customer::load_from_sql":
    require => Mysql::Create_database["${customer_database}"],
    unless => "test -f /vagrant/${customer_username}-db/${customer_database}.sql && \
              mysql --batch -u${customer_username} -p${customer_password} \
              -e 'SHOW TABLES' ${customer_database} | grep -q '^wp_users$'",
    command => "cat /vagrant/${customer_username}-db/${customer_database}.sql | \
                mysql --batch -u${customer_username} -p${customer_password} ${customer_database}",
  }

  ## Load data in WP if none present 
  exec {"customer::load_from_data":
    require => [Wordpress::Install["${customer_username}-site"],Package["rsync"]],
    unless => "test -d /var/www/${customer_username}-wp/wp-content/uploads/",
    command => "rsync -avz /vagrant/${customer_username}-data/ \
                /var/www/${customer_username}-wp/wp-content/uploads/ || \
                ( rm -fr /var/www/${customer_username}-wp/wp-content/uploads/ && false )",
    creates => "/var/www/${customer_username}-wp/wp-content/uploads/"
  }

  include wordpress
  wordpress::install{"${customer_username}-site":
      path              => "${customer_wp_path}",
      domain            => "${customer_domain}",
      database          => "${customer_database}",
      database_username => "${customer_username}",
      database_password => "${customer_password}"
  }

  host {"${customer_domain}":
      ip          => '127.0.0.1',
      host_aliases => ["www.${customer_domain}"],
  }


  file { ["${customer_wp_path}/wp-content", "${customer_wp_path}/wp-content/themes"]:
      ensure => 'directory',
      owner => "www-data",
      group => "www-data",
      recurse => true,
      mode => 755,
      require    => Wordpress::Install["${customer_username}-site"]

  }

  # create symlink to forge project
  file { "${customer_wp_path}/wp-content/themes/${customer_wp_theme}":
      ensure => 'link',
      target     => "/vagrant/${customer_wp_theme}/.forge/build",
      require    => File["${customer_wp_path}/wp-content/themes"]
  }

  #  wordpress::plugin{
  #    'multiple-content-blocks': 
  #      path => "${customer_wp_path}" ;
  #    'custom-post-widget.2.0.2':
  #      path => "${customer_wp_path}",
  #      rename_as => "custom-post-widget";
  #    'category-posts.3.3': 
  #      path => "${customer_wp_path}",
  #      rename_as => "category-posts";
  #    'fbf-facebook-page-feed-widget': 
  #      path => "${customer_wp_path}" ;
  #    'featured-video': 
  #      path => "${customer_wp_path}" ;
  #    'my-posts-order': 
  #      path => "${customer_wp_path}" ;
  #    'wp-paginate.1.2.4': 
  #      path => "${customer_wp_path}",
  #      rename_as => "wp-paginate"; 
  #    'googleanalytics': 
  #      path => "${customer_wp_path}" ;
  #    'wp-super-cache.1.2':
  #      path => "${customer_wp_path}",
  #      rename_as => "wp-super-cache";
  #  }

  # modify loop file in 'my-post-order'
  # file { "${customer_wp_path}/wp-content/plugins/my-posts-order/includes/custom-templates/loop.php":
  #  ensure => 'present',
  #  content => template("egraine/my-post-order-loop.php.erb"),
  #  require => [File["${customer_wp_path}/wp-content"],
  #          Wordpress::Plugin["my-posts-order"]]
  # }

  # FIXME: maybe active plugins ?

  include customer::packages
}

