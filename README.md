## (mini) Web gui for snooze

### For Grid'5000 user

Assuming that `ENV['USER']` is set to the same login as the one used on G5K frontends, you can launch : 

`BOOTSTRAP=yourbootstrapnode ruby g5k.rb`

It will set up tunneled connections to the bootstrap node.

### Otherwise

If your nodes are on the same network as the snoozeweb service you can launch : 

`ruby run.rb`






