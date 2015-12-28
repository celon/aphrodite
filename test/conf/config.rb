RABBITMQ_HOST = '127.0.0.1'
RABBITMQ_USER = 'bigdata'
RABBITMQ_PSWD = 'x'

REDIS_HOST = '127.0.0.1'
REDIS_PORT = 6379
REDIS_DB = 0
REDIS_PSWD = 'PtgpJDKr7HeuzKuSDsmmHSPVJue8wWaLPA'

DB_HOST = '127.0.0.1'
DB_USER = 'uranus'
DB_PSWD = 'x'
DB_NAME = 'gaia'
DB_PORT = 3306

Dir["#{File.dirname(__FILE__)}/*.rb"].each { |f| require f if f != __FILE__ }
