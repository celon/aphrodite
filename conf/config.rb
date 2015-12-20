# Conf example here.
RABBITMQ_HOST = '127.0.0.1'
RABBITMQ_USER = 'aphrodite'
RABBITMQ_PSWD = 'x'

REDIS_HOST = '127.0.0.1'
REDIS_PORT = 6379
REDIS_DB = 0
REDIS_PSWD = 'x'

DB_HOST = '127.0.0.1'
DB_USER = 'aphrodite'
DB_PSWD = 'x'
DB_NAME = 'aphrodite'
DB_PORT = 3306

Dir["#{File.dirname(__FILE__)}/*.rb"].each { |f| require f }
