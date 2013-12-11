require 'net/ssh/gateway'  
require './snoozeweb'

login = ENV['LOGIN'] || ENV['USER'] 
bootstrap = ENV['BOOTSTRAP']

config    = YAML.load_file("config.yml")

gateway = Net::SSH::Gateway.new("access.grid5000.fr",login)  
# snoozeimages
gateway.open(bootstrap, 4000 , 4000)
# snooze node bootstrap
gateway.open(bootstrap, 5000 , 5000)
# snooze ec2
gateway.open(bootstrap, 4001 , 4001)
# stomp protocol
gateway.open(bootstrap, 55674 , 55674)

SnoozeWeb.run!
