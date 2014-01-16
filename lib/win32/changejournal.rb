require 'socket'
require 'win32ole'
require 'timeout'

module Win32
  class ChangeJournal
    class Error < StandardError; end

    # The version of the win32-changejournal library
    VERSION = '0.4.0'

    Struct.new("ChangeJournalStruct", :action, :file_name, :path)

    attr_reader :path
    attr_reader :host

    def initialize(path, host = Socket.gethostname)
      @path = path.tr("/", "\\")
      @host = host
      @conn = "winmgmts:{impersonationlevel=impersonate}!//#{host}/root/cimv2"
    end

    def wait(seconds = nil)
      ole    = WIN32OLE.connect(@conn)
      drive  = @path.split(':').first + ":"
      folder = @path.split(':').last.gsub("\\", "\\\\\\\\")
      folder << "\\\\" unless folder[-1] == "\\"

      query = %Q{
        select * from __instanceOperationEvent
        within 2
        where targetInstance isa 'CIM_DataFile'
        and targetInstance.Drive='#{drive}'
        and targetInstance.Path='#{folder}'
      }

      sink  = WIN32OLE.new('WbemScripting.SWbemSink')
      event = WIN32OLE_EVENT.new(sink)

      ole.execNotificationQueryAsync(sink, query)
      sleep 0.5

      event.on_event("OnObjectReady"){ |object, context|
        #object.TargetInstance.Properties_.each{ |p|
        #  p p.Name
        #}
        #p object.Path_.Class
        #p object.TargetInstance.Path
        p object.TargetInstance.Name
        #p object.TargetInstance.Drive
        #puts "Modification of " + object.TargetInstance.Name
      }

      if seconds
        begin
          Timeout.timeout(seconds){
            loop do
              WIN32OLE_EVENT.message_loop
            end
          }
        rescue Timeout::Error
          # Do nothing, return control to user
        end
      else
        loop do
          WIN32OLE_EVENT.message_loop
        end
      end
    end
  end
end

if $0 == __FILE__
  #https://social.technet.microsoft.com/Forums/scriptcenter/en-US/445f54d2-3b0c-4984-86e0-22f5734b368a/vbscript-wmi-filesystemwatcher?forum=ITCG
  include Win32
  cj = ChangeJournal.new("C:/Users/djberge")
  cj.wait(10)
end
