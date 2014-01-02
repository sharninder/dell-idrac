provider_path = Pathname.new(__FILE__).parent.parent
require 'rexml/document'
include REXML
require File.join(provider_path, 'idrac')
require File.join(provider_path, 'checklcstatus')
require File.join(provider_path, 'checkjdstatus')
require File.join(provider_path, 'importtemplatexml')

Puppet::Type.type(:importnparsetting).provide(:importnparsetting, :parent => Puppet::Provider::Idrac) do
  desc "Dell idrac provider for  nic partitioning."
  $count = 0
  $maxcount = 30

  def create
    requiredstatus = resource[:status]
    targetnic = resource[:nic]

    file = File.new('/etc/puppet/modules/idrac/files/defaultxmls/nparsetting.xml')
    xmldoc = Document.new(file)
    
    xmldoc.elements.each("SystemConfiguration/Component") {
       |e|  e.attributes["FQDD"] = "#{targetnic}"
    }

    xmldoc.elements.each("SystemConfiguration/Component/Attribute") {
        |e|  if e.attributes["Name"] == "NicPartitioning"
                e.text = requiredstatus
            end
    }
    
    nparsettingfilename = "nparsetting_#{resource[:dracipaddress]}.xml"
    nparsettingfilepath = "#{resource[:nfssharepath]}/#{nparsettingfilename}"
    file = File.open("#{nparsettingfilepath}", "w")
    xmldoc.write(file)
    file.close

    #Import System Configuration
    obj = Puppet::Provider::Importtemplatexml.new(resource[:dracipaddress],resource[:dracusername],resource[:dracpassword],nparsettingfilename,resource[:nfsipaddress],resource[:nfssharepath])
    instanceid = obj.importtemplatexml
    puts "Instance id #{instanceid}"
    for i in 0..30
        obj = Puppet::Provider::Checkjdstatus.new(resource[:dracipaddress],resource[:dracusername],resource[:dracpassword],instanceid)
        response = obj.checkjdstatus
        puts "JD status : #{response}"
        if response  == "Completed"
            Puppet.info "Import NPAR settings is completed."
            break
        else
            Puppet.info "Job is running, wait for 1 minute"
            sleep 60
        end
    end
    if response != "Completed"
      raise "Import NPAR Settings is still running."
    end    

  end
  
  def exists?
    obj = Puppet::Provider::Checklcstatus.new(resource[:dracipaddress],resource[:dracusername],resource[:dracpassword])
    response = obj.checklcstatus
    response = response.to_i
    if response == 0
        return false
    else
        #recursive call  method exists till lcstatus =0
        while $count < $maxcount  do
            Puppet.info "LC status busy, wait for 1 minute"
            sleep 60
            $count +=1
            exists?
        end
        raise Puppet::Error, "Life cycle controller is busy"
        return true
    end
  end

end