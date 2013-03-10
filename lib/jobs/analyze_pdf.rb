require_relative './detect_rulings.rb'

########## PDF handling resque jobs ##########
class AnalyzePDFJob
  # args: (:file_id, :file, :output_dir)
  # Runs the jruby PDF analyzer on the uploaded file.
  include Resque::Plugins::Status
  Resque::Plugins::Status::Hash.expire_in = (30 * 60) # 30min
  @queue = :pdftohtml

  def perform
    file_id = options['file_id']
    file = options['file']
    output_dir = options['output_dir']
    upload_id = self.uuid

    filename = File.join(output_dir, 'document.pdf')

    # TODO might make sense to move this to a separate job
    at(0, 100, "generating thumbnails...",
       'file_id' => file_id,
       'upload_id' => upload_id
       )
    run_mupdfdraw(filename, output_dir, 560)
    at(5, 100, "generating thumbnails...",
       'file_id' => file_id,
       'upload_id' => upload_id
       )
    run_mupdfdraw(filename, output_dir, 2048)

    at(10, 100, "analyzing PDF text...",
       'file_id' => file_id,
       'upload_id' => upload_id,
       'thumbnails_complete' => true
       )

    i, o, e, thr = Open3.popen3(
                                {"CLASSPATH" => "lib/jars/fontbox-1.7.1.jar:lib/jars/pdfbox-1.7.1.jar:lib/jars/commons-logging-1.1.1.jar:lib/jars/jempbox-1.7.1.jar"},
                                "#{Settings::JRUBY_PATH} --1.9 --server lib/jruby_dump_characters.rb #{file} #{output_dir}"
                                )

    e.each { |line|
      progress, total = line.split('///', 2)

      next if progress.nil? || total.nil?

      progress = (progress.strip).to_i
      total = (total.strip).to_i
      if total === 0
        total = 1
      end

      converted_progress = (90 * progress / total).to_i + 10
      #puts "#{progress} of #{total} (#{converted_progress}%)"
      at(converted_progress, 100, "processing page #{progress} of #{total}...",
         'file_id' => file_id,
         'upload_id' => upload_id
         )
    }
    Process.wait(thr.pid)

    at(100, 100, "complete",
       'file_id' => file_id,
       'upload_id' => upload_id,
       'thumbnails_complete' => true
       )

  end
end
