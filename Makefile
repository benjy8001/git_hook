DOCKER_COMPOSE  = docker-compose

EXEC_PHP        = $(DOCKER_COMPOSE) exec -T application
CONNECT_PHP     = $(DOCKER_COMPOSE) exec application bash
LOCAL_APP_PATH  = webapp/

SYMFONY         = $(EXEC_PHP) bin/console
COMPOSER        = $(EXEC_PHP) composer
YARN            = $(EXEC_PHP) yarn

##
## Project
## -------
##

build: ## Build all containers
	$(DOCKER_COMPOSE) build

kill:
	$(DOCKER_COMPOSE) kill
	$(DOCKER_COMPOSE) down --volumes --remove-orphans

install: ## Install and start the project
install: .env build start assets db

reset: ## Stop and start a fresh install of the project
reset: kill install

start: ## Start the project
	$(DOCKER_COMPOSE) up -d --remove-orphans --no-recreate

connect: ## Connect to the container of the project
	$(CONNECT_PHP)

stop: ## Stop the project
	$(DOCKER_COMPOSE) stop

clean: ## Stop the project and remove generated files
clean: kill
	rm -rf .env vendor node_modules

no-docker:
	$(eval DOCKER_COMPOSE := \#)
	$(eval EXEC_PHP := )

.PHONY: build kill install reset start connect stop clean no-docker

##
## Utils
## -----
##

db: ## Reset the database and load fixtures
db: .env vendor
	@$(EXEC_PHP) php -r 'echo "Wait database...\n"; set_time_limit(15); require __DIR__."/vendor/autoload.php"; (new \Symfony\Component\Dotenv\Dotenv())->load(__DIR__."/.env"); $$u = parse_url(getenv("DATABASE_URL")); for(;;) { if(@fsockopen($$u["host"].":".($$u["port"] ?? 3306))) { break; }}'
	-$(SYMFONY) doctrine:database:drop --if-exists --force
	-$(SYMFONY) doctrine:database:create --if-not-exists
	$(SYMFONY) doctrine:migrations:migrate --no-interaction --allow-no-migration
	$(SYMFONY) doctrine:fixtures:load --no-interaction --purge-with-truncate

migration: ## Generate a new doctrine migration
migration: vendor
	$(SYMFONY) doctrine:migrations:diff

db-validate-schema: ## Validate the doctrine ORM mapping
db-validate-schema: .env vendor
	$(SYMFONY) doctrine:schema:validate

assets: ## Run Webpack Encore to compile assets
assets: node_modules
	@if [ -f $(LOCAL_APP_PATH)package.json ]; \
	then\
	    $(YARN) run dev;\
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

.PHONY: db migration assets watch

##
## Tests
## -----
##

test: ## Run unit and functional tests
test: tu tf

tu: ## Run unit tests
tu: vendor
	$(EXEC_PHP) bin/phpunit --exclude-group functional

tf: ## Run functional tests
tf: vendor
	$(EXEC_PHP) bin/phpunit --group functional

.PHONY: tests tu tf

# rules based on files
composer.lock: ## Run composer update
	$(COMPOSER) update --lock --no-scripts --no-interaction

vendor: ## Run composer install
	$(COMPOSER) install

node_modules: ## Run yarn
	$(YARN) install
	@touch -c node_modules

yarn.lock:
	@if [ -f $(LOCAL_APP_PATH)package.json ]; \
	then\
	    $(YARN) upgrade;\
	else\
		echo '\033[1;41m/!\ No package.json found.\033[0m';\
	fi

.env:
	@if [ -f $(LOCAL_APP_PATH).env ]; \
	then\
		echo '\033[1;41m/!\ The .env.dist file has changed. Please check your .env file (this message will not be displayed again).\033[0m';\
	else\
		echo cp .env.dist .env;\
		cp $(LOCAL_APP_PATH).env.dist $(LOCAL_APP_PATH).env;\
	fi

.PHONY: vendor node_modules

##
## Quality assurance
## -----------------
##

QA        = docker run --rm -v `pwd`/$(LOCAL_APP_PATH):/project mykiwi/phaudit:7.2
ARTEFACTS = $(LOCAL_APP_PATH)var/artefacts/phpmetrics

lint: ## Lints twig and yaml files
lint: lt ly

lt: vendor
	$(SYMFONY) lint:twig templates

ly: vendor
	$(SYMFONY) lint:yaml config

security: ## Check security of your dependencies (https://security.sensiolabs.org/)
security: vendor
	$(EXEC_PHP) bin/console security:check

phploc: ## PHPLoc (https://github.com/sebastianbergmann/phploc)
	$(QA) phploc src/

pdepend: ## PHP_Depend (https://pdepend.org)
pdepend: artefacts
	$(QA) pdepend \
		--summary-xml=$(ARTEFACTS)/pdepend_summary.xml \
		--jdepend-chart=$(ARTEFACTS)/pdepend_jdepend.svg \
		--overview-pyramid=$(ARTEFACTS)/pdepend_pyramid.svg \
		src/

phpmd: ## PHP Mess Detector (https://phpmd.org)
	$(QA) phpmd src text .phpmd.xml

php_codesnifer: ## PHP_CodeSnifer (https://github.com/squizlabs/PHP_CodeSniffer)
	$(QA) phpcs -v --standard=.phpcs.xml src

phpcpd: ## PHP Copy/Paste Detector (https://github.com/sebastianbergmann/phpcpd)
	$(QA) phpcpd src

phpdcd: ## PHP Dead Code Detector (https://github.com/sebastianbergmann/phpdcd)
	$(QA) phpdcd src

phpmetrics: ## PhpMetrics (http://www.phpmetrics.org)
phpmetrics: artefacts
	$(QA) phpmetrics --report-html=$(ARTEFACTS)/phpmetrics src

php-cs-fixer: ## php-cs-fixer (http://cs.sensiolabs.org)
	$(QA) php-cs-fixer fix --dry-run --using-cache=no --verbose --diff

apply-php-cs-fixer: ## apply php-cs-fixer fixes
	$(QA) php-cs-fixer fix --using-cache=no --verbose --diff

twigcs: ## twigcs (https://github.com/allocine/twigcs)
	$(QA) twigcs lint templates

eslint: ## eslint (https://eslint.org/)
eslint: node_modules
	$(EXEC_JS) node_modules/.bin/eslint --fix-dry-run assets/js/**

artefacts:
	mkdir -p $(ARTEFACTS)

.PHONY: lint lt ly phploc pdepend phpmd php_codesnifer phpcpd phpdcd phpmetrics php-cs-fixer apply-php-cs-fixer artefacts



.DEFAULT_GOAL := help
help:
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'
.PHONY: help