require 'ffi'
require File.join(File.dirname(__FILE__), 'changejournal', 'constants')
require File.join(File.dirname(__FILE__), 'changejournal', 'structs')
require File.join(File.dirname(__FILE__), 'changejournal', 'functions')

module Win32
  class ChangeJournal
    include Windows::ChangeJournal::Constants
    include Windows::ChangeJournal::Structs
    include Windows::ChangeJournal::Functions

    # The version of the win32-changejournal library.
    VERSION = '0.4.0'

    def initialize(drive = 'C:')
      flags = File.directory?(drive) ? FILE_FLAG_BACKUP_SEMANTICS : 0

      drive = "\\\\.\\" << drive << 0.chr
      drive.encode!('UTF-16LE')

      handle = CreateFile(
        drive,
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nil,
        OPEN_EXISTING,
        flags,
        0
      )

      if handle == INVALID_HANDLE_VALUE
        raise SystemCallError.new("CreateFile", FFI.errno)
      end

      begin
        bytes = FFI::MemoryPointer.new(:ulong)
        journal_data = USN_JOURNAL_DATA.new

        bool = DeviceIoControl(
          handle,
          FSCTL_QUERY_USN_JOURNAL(),
          nil,
          0,
          journal_data,
          journal_data.size,
          bytes,
          nil
        )

        unless bool
          raise_windows_error('DeviceIoControl')
        end

        read_data = READ_USN_JOURNAL_DATA.new
        read_data[:StartUsn] = 0
        read_data[:ReasonMask] = 0xFFFFFFFF
        read_data[:ReturnOnlyOnClose] = false
        read_data[:Timeout] = 0
        read_data[:BytesToWaitFor] = 0
        read_data[:UsnJournalID] = journal_data[:UsnJournalID]

        buffer = FFI::MemoryPointer.new(:char, 4096)
        bytes  = FFI::MemoryPointer.new(:ulong)

        bool = DeviceIoControl(
          handle,
          FSCTL_READ_USN_JOURNAL(),
          read_data,
          read_data.size,
          buffer,
          buffer.size,
          bytes,
          nil
        )

        unless bool
          raise_windows_error('DeviceIoControl')
        end

        usn = FFI::MemoryPointer.new(:double) # USN data type
        ret_bytes = bytes.read_ulong - usn.size

        usn_rec = USN_RECORD.new(buffer)
        p usn_rec[:RecordLength]
        p usn_rec[:FileNameLength]
        p usn_rec[:FileName]

        #while ret_bytes > 0
        #  usn_rec[:FileName].read_bytes(usn_rec[:FileNameLength]/2)
        #  ret_bytes -= usn_rec[:RecordLength]
        #end
      ensure
        CloseHandle(handle)
      end
    end

    private

    def EnumNext(handle)
      unless @buffer
        raise "no buffer to use"
      end

      @usn_record = nil

      bool = DeviceIoControl(
        handle,
        FSCTL_READ_USN_JOURNAL(),
        @rujd,
        @rujd.size,
        @buffer,
        HeapSize(GetProcessHeap(), 0, @buffer),
        @bytes,
        nil
      )

      if bool
        SetLastError(0) # NO_ERROR
        @rujd[:StartUsn] = @buffer
        usn = FFI::MemoryPointer.new(:double)

        if @bytes > usn.size
          @usn_record = @buffer[usn.size]
        end
      else
        @usn_record = @usn_record + @usn_record[:RecordLength]
      end
    end

    def SeekToUsn(usn, reason, returnonly, journalid)
      @rujd[:StartUsn]          = usn
      @rujd[:ReasonMask]        = reason
      @rujd[:ReturnOnlyOnClose] = returnonly
      @rujd[:Timeout]           = 0
      @rujd[:BytesToWaitFor]    = 0
      @rujd[:UsnJournalID]      = journalid

      @bytes = 0
      @usn_record = nil
    end

    def Query(handle, journal_data)
      bytes = FFI::MemoryPointer.new(:ulong)

      bool = DeviceIoControl(
        handle,
        FSCTL_QUERY_USN_JOURNAL(),
        nil,
        0,
        journal_data,
        journal_data.size,
        bytes,
        nil
      )

      bool
    end

    def Delete(handle, journalid, flags)
      bytes = FFI::MemoryPointer.new(:ulong)
      dujd  = DELETE_USN_JOURNAL_DATA.new

      dujd[:UsnJournalID] = journalid
      dujd[:DeleteFlags]  = flags

      bool = DeviceIoControl(
        handle,
        FSCTL_DELETE_USN_JOURNAL(),
        dujd,
        dujd.size,
        nil,
        0,
        bytes,
        nil
      )

      bool
    end

    def Create(handle, maxsize, delta)
      bytes = FFI::MemoryPointer.new(:ulong)
      cujd  = CREATE_USN_JOURNAL_DATA.new

      cujd[:MaximumSize] = maxsize
      cujd[:AllocationDelta] = delta

      bool = DeviceIoControl(
        handle,
        FSCTL_CREATE_USN_JOURNAL(),
        cujd,
        cujd.size,
        nil,
        0,
        bytes,
        NULL
      )

      bool
    end

    def Open(drive, access = nil, async = false)
      flags = async ? FILE_FLAG_OVERLAPPED : 0
      access ||= GENERIC_READ | GENERIC_WRITE,

      drive = "\\\\.\\" << drive << 0.chr
      drive.encode!('UTF-16LE')

      handle = CreateFile(
        file,
        access,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nil,
        OPEN_EXISTING,
        flags,
        0
      )

      if handle == INVALID_HANDLE_VALUE
        raise_windows_error
      end
    end
  end
end

if $0 == __FILE__
  # Run with admin privileges
  cj = Win32::ChangeJournal.new
end
