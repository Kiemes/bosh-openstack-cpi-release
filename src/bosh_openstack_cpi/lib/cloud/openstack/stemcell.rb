module Bosh::OpenStackCloud
  class Stemcell
    include Helpers

    def self.create_instance(logger, openstack)
      if openstack.image.class.to_s.include?('Fog::Image::OpenStack::V1')
        StemcellV1.new(logger, openstack)
      else
        StemcellV2.new(logger, openstack)
      end
    end

    def initialize(logger, openstack)
      @logger = logger
      @openstack = openstack
    end

  end

  class StemcellHeavy < Stemcell

    def initialize(*args)
      super
    end

    def create(image_path, cloud_properties, is_public)
      begin
        Dir.mktmpdir do |tmp_dir|
          @logger.info('Creating new image...')

          image_params = {
            :name => "#{cloud_properties['name']}/#{cloud_properties['version']}",
            :disk_format => cloud_properties['disk_format'],
            :container_format => cloud_properties['container_format'],
          }

          set_public_param(image_params, is_public)

          image_properties = normalize_image_properties(cloud_properties)

          set_image_properties(image_params, image_properties)

          @logger.info("Extracting stemcell file to `#{tmp_dir}'...")
          unpack_image(tmp_dir, image_path)

          image_location = File.join(tmp_dir, 'root.img')
          image = upload(image_params, image_location)

          @logger.info("Waiting for image '#{image.id}' to have status 'active'...")
          wait_resource(image, :active)

          image.id.to_s
        end
      rescue => e
        @logger.error(e)
        raise e
      end
    end

    def create_openstack_image(image_params)
      @logger.debug("Using image parms: `#{image_params.inspect}'")
      with_openstack { @openstack.image.images.create(image_params) }
    end

    def unpack_image(tmp_dir, image_path)
      result = Bosh::Exec.sh("tar -C #{tmp_dir} -xzf #{image_path} 2>&1", :on_error => :return)
      if result.failed?
        @logger.error("Extracting stemcell root image failed in dir #{tmp_dir}, " +
          "tar returned #{result.exit_status}, output: #{result.output}")
        cloud_error('Extracting stemcell root image failed. Check task debug log for details.')
      end
      root_image = File.join(tmp_dir, 'root.img')
      unless File.exists?(root_image)
        cloud_error('Root image is missing from stemcell archive')
      end
    end

    def normalize_image_properties(properties)
      image_properties = {}
      image_options = ['version', 'os_type', 'os_distro', 'architecture', 'auto_disk_config',
        'hw_vif_model', 'hypervisor_type', 'vmware_adaptertype', 'vmware_disktype',
        'vmware_linked_clone', 'vmware_ostype']
      image_options.reject { |image_option| properties[property_option_for_image_option(image_option)].nil? }.each do |image_option|
        image_properties[image_option.to_sym] = properties[property_option_for_image_option(image_option)].to_s
      end
      image_properties
    end

    def property_option_for_image_option(image_option)
      if image_option == 'hypervisor_type'
        'hypervisor'
      else
        image_option
      end
    end
  end

  class StemcellV1 < StemcellHeavy
    def initialize(*args)
      super
    end

    def set_public_param(image_params, is_public)
      image_params[:is_public] = is_public
    end

    def set_image_properties(image_params, image_properties)
      image_params[:properties] = image_properties unless image_properties.empty?
    end

    def upload(image_params, image_location)
      image_params[:location] = image_location
      create_openstack_image(image_params)
    end

  end

  class StemcellV2 < StemcellHeavy
    def initialize(*args)
      super
    end

    def set_public_param(image_params, is_public)
      image_params[:visibility] = is_public ? 'public' : 'private'
    end

    def set_image_properties(image_params, image_properties)
      image_params.merge!(image_properties)
    end

    def upload(image_params, image_location)
      image = create_openstack_image(image_params)
      wait_resource(image, :queued)
      @logger.info("Performing file upload for image: '#{image.id}'...")
      image.upload_data(File.open(image_location, 'rb'))
      image
    end
  end
end