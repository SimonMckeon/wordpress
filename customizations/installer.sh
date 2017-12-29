#!/usr/bin/env bash

cwd=$(pwd)

if [[ $cwd == *"customizations"* ]]; then
  echo "You're doing it wrong. You should run install.sh from project root, and nothing from customizations folder."
  exit 1
fi


source customizations/helpers.sh
source customizations/theme-installer.sh

conquer() {
  echo "Conquering the world..."
  echo -ne '##                    (10%)\r'
  sleep_fraction 0.1
  echo -ne '######                (30%)\r'
  sleep_fraction 0.5
  echo -ne '##############        (60%)\r'
  sleep 1
  echo -ne '##################### (100%)\r'
  echo -ne '\n'
  echo
}

add_scripts() {
  echo "Adding /data/wordpress/customizations/bin to PATH"
  run /data/wordpress/customizations/path-add.sh
}

backup() {
  echo "Enabling backups of the database..."
  run /data/wordpress/customizations/vagrant-cron.sh &> /dev/null # It never fails, stop whining about "no crontab for vagrant"
  echo

  echo "Backing the database up..."
  run /data/wordpress/customizations/database-backup.sh
  echo
}

replace_readme() {
  if git log | grep --quiet '\[auto\] Replace README'; then
    echo "README has been replaced already, skipping task..."
    return
  fi

  echo "Replacing README..."

  git stash # Save any changes for now

  rm README.md
  cp customizations/README-sample.md README.md
  git add README.md
  git commit -m "[auto] Replace README"

  git stash pop # bring the changes back
}

composertask() {
  if ! grep --quiet "seravo/wordpress" composer.json; then
    echo "composer.json didn't contain seravo/wordpress, skipping task."
    return
  fi

  echo "Replacing composer.json..."
  rm composer.json composer.lock # I just don't want to deal with cp
  cp customizations/composer-sample.json composer.json # TODO: Maybe make it modular?

  echo "Removing existing plugins..."
  rm -rf vendor
  rm -rf htdocs/wp-content/plugins/*

  echo "Updating Composer mirrors..."
  composer update mirrors # To actually use the Private Packagist that we just enabled

  echo "Running composer install..."
  composer install

  echo
}

plugins() {
  echo "Turning all plugins on..."
  run "wp plugin list --status=inactive --field=name --format=csv | xargs sudo -u vagrant -i -- wp plugin activate --quiet"
  echo
}

admin() {
  echo "Setting the language to English (US)..."
  echo "Prefer something else? Create an user account and select the language you want to use. WordPress should be en_US for performance and developer happiness."
  run "wp language core activate en_US"
  echo

  # echo "Checking if the default user still exists..."
  user_id=$(run "wp user get vagrant --field=ID --skip-plugins --skip-themes") # Notices break things
  if grep --quiet Error <<< "$user_id"; then
    user_id=0 # The interpreter will be very sad if this isn't a number.
  fi
  user_id=${user_id//[^0-9]*/} # Sanitize the value, strip everything else out.

  if [ "$user_id" -eq 1 ]; then
    echo "Removing the default user..."
    run "wp user delete $user_id --yes"

    echo "Creating a new admin user..."
    password=$(openssl rand -base64 32 2> /dev/null | head -c32)
    run "wp user create 'vincit.admin' wordpress@vincit.fi --role='administrator' --display_name='Administrator' --user_pass='$password'"
    echo "Username: vincit.admin"
    echo "Password: $password"
  else
    echo "Default user wasn't found, skipping user deletion and creation..."
  fi
  echo
}

ignore() {
  echo "Checking if there's any files that shouldn't be tracked in Git..."
  gitignore=$(<.gitignore)

  if ! grep --quiet "/.vincit.d" <<< "$gitignore"; then
    echo "Ignoring /.vincit.d (used to detect installation status)"
    echo /.vincit.d >> .gitignore
  fi

  if ! grep --quiet "/customizations" <<< "$gitignore"; then
    echo "Ignoring /customizations/ (managed by Composer)"
    echo /customizations >> .gitignore
  fi

  if ! grep --quiet "!/customizations/bin" <<< "$gitignore"; then
    echo "Un-ignoring /customizations/bin (you retain your scripts)"
    echo !/customizations/bin >> .gitignore
  fi

  if ! grep --quiet "/install.sh" <<< "$gitignore"; then
    echo "Ignoring /install.sh (managed by Composer)"
    echo /install.sh >> .gitignore
  fi

  if ! grep --quiet "/vagrant-up-customizer.sh" <<< "$gitignore"; then
    echo "Ignoring vagrant-up-customizer.sh (managed by Composer)"
    echo /vagrant-up-customizer.sh >> .gitignore
  fi
}

tune_hooks() {
  echo "Moving pre-commit hook that runs *slow* rspec tests to pre-push..."
  mv .git/hooks/pre-commit .git/hooks/pre-push
  echo

}

install() {
  echo "Running the installer..."
  echo
  for fn in "$@"; do
    eval "$fn"
  done
}

installer() {
  # Run full installer if this file doesn't exist.

  if [ ! -f .vincit.d ]; then
    install "conquer" "replace_readme" "add_scripts" "backup" "composertask" "plugins" "prompt_theme_installer" "admin" "ignore" "tune_hooks"
    touch .vincit.d
  else
    # Run these tasks every time
    install "conquer" "backup" "admin" "ignore"
  fi

  echo
  echo "Missing something? You can run this installation wizard manually."
  echo "$ ./install.sh"
  echo

  exit 0
}
