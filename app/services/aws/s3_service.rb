class AWS::S3Service
  def initialize
    @s3_client = Aws::S3::Client.new(
      access_key_id: ENV['AWS_ACCESS_KEY'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
      region: ENV['AWS_REGION']
    )
  end

  def bucket_name
    ENV['AWS_BUCKET_NAME']
  end

  def upload_file(file_path, object_key)
    File.open(file_path, 'rb') do |file|
      @s3_client.put_object(bucket: bucket_name, key: object_key, body: file)
    end
  end

  def download_file(object_key, download_path)
    File.open(download_path, 'wb') do |file|
      @s3_client.get_object({ bucket: bucket_name, key: object_key }, target: file)
    end
  end

  def delete_file(object_key)
    @s3_client.delete_object(bucket: bucket_name, key: object_key)
  end
end
