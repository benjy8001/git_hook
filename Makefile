# on affiche pas les commandes par defaut

ifndef VERBOSE
.SILENT:
endif
EXIT_CODE = 0
ifeq ($(origin CI), undefined)
EXIT_CODE = 1
endif


DOCKER_COMPOSE  = docker-compose

EXEC_PHP        = $(DOCKER_COMPOSE) exec -T php /entrypoint
EXEC_TEST        = $(DOCKER_COMPOSE) exec -T php /entrypoint bash -c
EXEC_JS         = $(DOCKER_COMPOSE) exec -T node /entrypoint

CONNECT_PHP     = $(DOCKER_COMPOSE) exec php sh
LOCAL_APP_PATH  = webapp/

SYMFONY         = $(EXEC_PHP) bin/console
SYMFONY_BIG_MEM = $(EXEC_PHP) php -d memory_limit=-1 bin/console
COMPOSER        = $(EXEC_PHP) composer
YARN            = $(EXEC_JS) yarn

# Dossier de recherche des fichier pour make
# on l'autorise a chercher les dossiers cible dans le dossier webapp egalement
VPATH = .:./webapp
#PS note quand une recette ne doit pas créer de fichier il faut la mettre en .phony

# Install help commands
coffee:
	printf "\033[32m You can go take a coffee while we work for you \033[0m\n"

login-sudo: # demande le login utilisateur
	printf "\033[32m Please enter your password \033[0m\n"
	sudo printf "\033[32m thanxs \033[0m\n"

docker-login:
	printf "\033[32m Please enter your gitlab authentification \033[0m\n"
	docker login registry.gitlab.com

host-manager: login-sudo
	wget -q https://gitlab.com/snippets/1730128/raw -O host-manager
	chmod +x host-manager

add-hosts:host-manager
	sudo ./host-manager -add front.local.test.fr 127.0.0.1

remove-hosts:login-sudo
	sudo ./host-manager -remove front.local.test.fr

.ONESHELL:
add-hooks:
	if [ ! -f .git/hooks/change_detector.sh ]
	then
		cp .hooks/change_detector.sh .git/hooks/change_detector.sh
		chmod u+x  .git/hooks/change_detector.sh
	fi
	if [ ! -f .git/hooks/pre-push ]
	then
		cp .hooks/pre-push .git/hooks/pre-push
	fi
	if [ ! -f .git/hooks/pre-commit ]
	then
		cp .hooks/pre-commit .git/hooks/pre-commit
		cp .hooks/junk-words .git/hooks/junk-words
	fi
	if [ ! -f .git/hooks/commit-msg ]
	then
		cp .hooks/commit-msg .git/hooks/commit-msg
	fi

.PHONY: login-sudo coffee add-hosts

##
## Project
## -------
##

kill:
	$(DOCKER_COMPOSE) kill
	$(DOCKER_COMPOSE) down --volumes --remove-orphans

install: ## Install and start the project
install:banner login-sudo docker-login coffee add-hooks add-hosts start assets db

reset: ## Stop and start a fresh install of the project
reset: kill install

start: docker-compose.yml .env.local ## Start the project
	$(DOCKER_COMPOSE) pull
	$(DOCKER_COMPOSE) up -d --remove-orphans db http php node


start-gitlab: docker-compose.yml .env.local
	$(DOCKER_COMPOSE) up -d --remove-orphans php


connect: ## Connect to the container of the project
	$(CONNECT_PHP)

stop: ## Stop the project
	$(DOCKER_COMPOSE) stop

restart: ## (Alias) Stop and Start project
	make stop
	make start

clean: ## Stop the project and remove generated files
.ONESHELL:
clean:
	if [ -f docker-compose.yml ];
	then
		make kill
		rm docker-compose.yml
	fi
	if [ -f host-manager ];
	then
		make remove-hosts
		rm host-manager
	fi
	cd webapp && rm -rf .env.local vendor node_modules

check:
	@if [ -f $(LOCAL_APP_PATH)vendor/autoload.php ]; \
	then\
		echo autoload is ok; \
	else\
		rm -fr $(LOCAL_APP_PATH)vendor;\
	fi

no-docker:
	$(eval DOCKER_COMPOSE := \#)
	$(eval EXEC_PHP := )

.PHONY: kill install reset start start-gitlab connect stop restart clean no-docker check

##
## Utils
## -----
##

create-db: ## Reset database
create-db: .env.local
	$(EXEC_PHP) php -r 'echo "Wait database...\n"; set_time_limit(15); require __DIR__."/vendor/autoload.php"; (new \Symfony\Component\Dotenv\Dotenv())->load(__DIR__."/.env"); $$u = parse_url(getenv("DATABASE_URL")); for(;;) { if(@fsockopen($$u["host"].":".($$u["port"] ?? 3306))) { break; }}'
	$(SYMFONY) doctrine:database:drop --if-exists --force
	$(SYMFONY) doctrine:database:create --if-not-exists
	$(SYMFONY) doctrine:migrations:migrate --no-interaction --allow-no-migration

db: ## Reset the database and load fixtures
db: .env.local create-db
	$(SYMFONY_BIG_MEM) doctrine:fixtures:load --no-interaction
	make load-fixtures

load-fixtures:
	$(SYMFONY_BIG_MEM) hautelook:fixtures:load -n --append

promot-admin:
	    $(SYMFONY) security:user:promote admin@test.com ROLE_SUPER_ADMIN

migration: ## Generate a new doctrine migration
migration: vendor
	$(SYMFONY) doctrine:migrations:diff

migrate: ## Play lastest doctrine migrations
migrate:
	$(SYMFONY) doctrine:migrations:migrate --no-interaction --allow-no-migration

db-validate-schema: ## Validate the doctrine ORM mapping
db-validate-schema: .env.local vendor
	$(SYMFONY) doctrine:schema:validate

assets: ## Run Webpack Encore to compile assets in dev mode
assets: vendor node_modules
	@if [ -f $(LOCAL_APP_PATH)package.json ]; \
	then\
	    $(YARN) run dev;\
	else\
		echo '\033[1;41m/!\ No package.json found.\033[0m';\
	fi

prod-assets: ## Run Webpack Encore to compile assets in production mode
prod-assets: vendor node_modules
	@if [ -f $(LOCAL_APP_PATH)package.json ]; \
	then\
	    $(YARN) run build;\
	else\
		echo '\033[1;41m/!\ No package.json found.\033[0m';\
	fi

watch: ## Run Webpack Encore in watch mode
watch: node_modules
	@if [ -f $(LOCAL_APP_PATH)package.json ]; \
	then\
	    $(YARN) run watch;\
	else\
		echo '\033[1;41m/!\ No package.json found.\033[0m';\
	fi

.PHONY: db migration assets prod-assets watch db-validate-schema

##
## Tests
## -----
##

test: ## Run unit and functional tests
test: tu tf

tu: ## Run unit tests
tu: vendor
	$(EXEC_TEST) "APP_ENV=test bin/phpunit --exclude-group functional --exclude-group databased,api"

tf: ## Run functional tests
tf: vendor
	$(EXEC_TEST) "APP_ENV=test bin/phpunit --group functional"


td: ## Run databased tests
td: vendor
	$(EXEC_TEST) "APP_ENV=test bin/phpunit --group databased"


ta: vendor ## Run API Tests
	$(EXEC_TEST) "APP_ENV=test bin/phpunit --group api"

.PHONY: tests tu tf td ta

# rules based on files
version: ## create version file
	echo "parameters:" > webapp/VERSION.yaml
	@TAG=$$(\git describe --exact-match --tags $$(git log -n1 --pretty='%h') 2> /dev/null ||echo $$(\git describe --tags --abbrev=0)-dev) && echo "  build.version: "$$TAG.$(CI_PIPELINE_IID) >> webapp/VERSION.yaml
	@TAG=$$(\git describe --exact-match --tags $$(git log -n1 --pretty='%h') 2> /dev/null ||echo $$(\git describe --tags --abbrev=0)-dev) && echo $$TAG.$(CI_PIPELINE_IID) > webapp/VERSION
composer.lock: ## Run composer update
	$(COMPOSER) update --lock --no-scripts --no-interaction

vendor: composer.lock ## Run composer install
	$(COMPOSER) install

node_modules: yarn.lock## Run yarn
	$(YARN) install
	@touch -c node_modules

yarn.lock:
	@if [ -f $(LOCAL_APP_PATH)package.json ]; \
	then\
	    $(YARN) upgrade;\
	else\
		echo '\033[1;41m/!\ No package.json found.\033[0m';\
	fi

.ONESHELL:
.env.local: .env
	if [ -f webapp/.env.local ];
	then
		echo '\033[1;41m/!\ The webapp/.env file has changed. Please check your webapp/.env.local file (this message will not be displayed again).\033[0m'
		touch webapp/.env.local
		exit $(EXIT_CODE)
	else
		echo cp webapp/.env webapp/.env.local
		cp webapp/.env webapp/.env.local
	fi
.ONESHELL:
docker-compose.yml: docker-compose.dist.yml
	if [ -f docker-compose.yml ];
	then
		echo '\033[1;41m/!\ The docker-compose.dist.yml file has changed. Please check your docker-compose.yml file (this message will not be displayed again).\033[0m'
		touch docker-compose.yml
		exit $(EXIT_CODE)
	else
		echo cp docker-compose.dist.yml docker-compose.yml
		cp docker-compose.dist.yml docker-compose.yml
	fi

##
## Quality assurance
## -----------------
##
IMAGE_AUDIT = mykiwi/phaudit:7.2
QA        = docker run --rm -v `pwd`/$(LOCAL_APP_PATH):/project $(IMAGE_AUDIT)
LOCAL_ARTEFACTS = var/artefacts
ARTEFACTS = $(LOCAL_APP_PATH)/$(LOCAL_ARTEFACTS)


lint: ## Lints twig and yaml files
lint: lt ly

lt: vendor
	$(SYMFONY) lint:twig templates

ly: vendor
	$(SYMFONY) lint:yaml config

security: ## Check security of your dependencies (https://security.sensiolabs.org/)
security:
	$(QA) security-checker security:check

phploc: ## PHPLoc (https://github.com/sebastianbergmann/phploc)
	$(QA) phploc src/

pdepend: ## PHP_Depend (https://pdepend.org)
pdepend: artefacts
	$(QA) pdepend \
		--summary-xml=$(LOCAL_ARTEFACTS)/pdepend_summary.xml \
		--jdepend-chart=$(LOCAL_ARTEFACTS)/pdepend_jdepend.svg \
		--overview-pyramid=$(LOCAL_ARTEFACTS)/pdepend_pyramid.svg \
		src/

phpmd: ## PHP Mess Detector (https://phpmd.org)
	$(QA) phpmd src text .phpmd.xml

php_codesnifer: ## PHP_CodeSnifer (https://github.com/squizlabs/PHP_CodeSniffer)
	$(QA) phpcs -v --standard=.phpcs.xml src

phpcpd: ## PHP Copy/Paste Detector (https://github.com/sebastianbergmann/phpcpd)
	$(QA) phpcpd src

phpmetrics: ## PhpMetrics (http://www.phpmetrics.org)
phpmetrics: artefacts
	$(QA) phpmetrics --report-html=$(LOCAL_ARTEFACTS)/phpmetrics src

php-cs-fixer: ## php-cs-fixer (http://cs.sensiolabs.org)
	docker pull $(IMAGE_AUDIT)
	$(QA) php-cs-fixer fix --dry-run --using-cache=no --verbose --diff

apply-php-cs-fixer: ## apply php-cs-fixer fixes
	docker pull $(IMAGE_AUDIT)
	$(QA) php-cs-fixer fix --using-cache=no --verbose --diff

phpstan: ## PHP Static Analysis Tool (https://github.com/phpstan/phpstan)
	$(QA) phpstan analyse -l 0 -c .phpstan.neon --memory-limit=512M src

twigcs: ## twigcs (https://github.com/allocine/twigcs)
	$(QA) twigcs lint  --severity=error templates

eslint: ## eslint (https://eslint.org/)
eslint: node_modules
	$(EXEC_JS) node_modules/.bin/eslint --fix-dry-run assets/js/**

artefacts:
	mkdir -p $(ARTEFACTS)

.PHONY: lint lt ly phploc pdepend phpmd php_codesnifer phpcpd phpdcd phpmetrics php-cs-fixer apply-php-cs-fixer artefacts


pre-commit:banner
	echo "make apply-php-cs-fixer"
	echo "make twigcs"
	echo "make phpcpd"
	echo "make php_codesnifer"



.DEFAULT_GOAL := help
banner:
	printf "\n"
	printf "\033[32m  __ )    \     \  |  \  | ____|  _ \   \033[0m\n"
	printf "\033[32m  __ \   _ \     \ |   \ | __|   |   |   \033[0m\n"
	printf "\033[32m  |   | ___ \  |\  | |\  | |     __ <    \033[0m\n"
	printf "\033[32m ____/_/    _\_| \_|_| \_|_____|_| \_\   \033[0m\n"

##
help:banner


.DEFAULT_GOAL := help
help:
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'
.PHONY: help
