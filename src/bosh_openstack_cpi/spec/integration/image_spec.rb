require_relative './spec_helper'

describe Bosh::OpenStackCloud::Cloud do
  include Bosh::OpenStackCloud::Helpers

  before(:all) do
    @config = IntegrationConfig.new
  end

  let(:logger) { Logger.new(STDERR) }

  before do
    delegate = double('delegate', logger: logger, cpi_task_log: nil)
    Bosh::Clouds::Config.configure(delegate)
    allow(Bosh::Clouds::Config).to receive(:logger).and_return(logger)
  end

  describe 'Glance V2 support' do
    let(:cpi_for_stemcell) { @config.create_cpi }

    before do
      expect(cpi_for_stemcell.glance.class.to_s).to start_with('Fog::Image::OpenStack::V2')
    end

    it 'uploads and deletes a stemcell' do
      stemcell_id, stemcell_manifest = upload_stemcell(cpi_for_stemcell, @config.stemcell_path)
      expect(stemcell_id).to_not be_nil

      image = cpi_for_stemcell.glance.images.get(stemcell_id)
      expect(image).to_not be_nil
      expect(image.name).to eq("#{stemcell_manifest['cloud_properties']['name']}/#{stemcell_manifest['cloud_properties']['version']}")
      expect(image.visibility).to eq('private')
      expect(image.os_distro).to eq('ubuntu')

      cpi_for_stemcell.delete_stemcell(stemcell_id)
      wait_resource(image, :deleted, :status, true)
    end
  end

  describe 'Glance V1 support' do
    let(:cpi_for_stemcell) { @config.create_cpi }

    def force_image_v1
      allow(Fog::Image::OpenStack::V2).to receive(:new).and_raise(Fog::OpenStack::Errors::ServiceUnavailable)
    end

    before do
      force_image_v1
    end

    it 'uploads and deletes a stemcell' do
      expect(cpi_for_stemcell.glance.class.to_s).to start_with('Fog::Image::OpenStack::V1')

      stemcell_id, stemcell_manifest = upload_stemcell(cpi_for_stemcell, @config.stemcell_path)
      expect(stemcell_id).to_not be_nil

      image = cpi_for_stemcell.glance.images.get(stemcell_id)
      expect(image).to_not be_nil
      expect(image.name).to eq("#{stemcell_manifest['cloud_properties']['name']}/#{stemcell_manifest['cloud_properties']['version']}")
      expect(image.is_public).to be(false)
      expect(image.properties).to include('os_distro' => 'ubuntu')

      cpi_for_stemcell.delete_stemcell(stemcell_id)
      wait_resource(image, :deleted, :status, true)
    end
  end

end

