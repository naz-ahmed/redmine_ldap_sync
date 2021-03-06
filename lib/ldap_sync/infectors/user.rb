module LdapSync::Infectors::User
  ::User::STANDARD_FIELDS = %w( firstname lastname mail )

  module InstanceMethods
    def add_to_fixed_group
      return unless auth_source.try :has_fixed_group?

      self.groups << ::Group.find_or_create_by_lastname(auth_source.fixed_group)
    end

    def sync_fields_and_groups
      return unless sync_on_create?

      auth_source.sync_user(self, false, :login => login, :password => password, :try_to_login => true)
    end

    def set_default_values
      custom_fields = UserCustomField.where("default_value is not null")
      self.custom_field_values = custom_fields.each_with_object({}) do |f, h|
        h[f.id] = f.default_value
      end

      self.language = Setting.default_language
      self.mail_notification = Setting.default_notification_option
    end

    def synced_fields=(attrs)
      self.attributes = attrs.slice(*::User::STANDARD_FIELDS)
      self.custom_field_values = attrs.except(*::User::STANDARD_FIELDS)
    end

    def member_of_group?(groupname)
      self.groups.exists?(:lastname => groupname)
    end

    def set_admin!
      self.update_attribute(:admin, true)
    end

    def unset_admin!
      self.update_attribute(:admin, false)
    end

    def sync_on_create!; @sync_on_create = true; end
    def sync_on_create?; @sync_on_create == true; end
  end

  module ClassMethods
    def try_to_login_with_ldap_sync(*args)
      user = try_to_login_without_ldap_sync(*args)
      return user unless user.try(:sync_on_login?)

      login, password = *args
      if user.new_record?
        user.sync_on_create!
        user unless user.auth_source.locked_on_ldap?(user,
          :login => login,
          :password => password)
      else
        user.auth_source.sync_user(user, false, :login => login, :password => password, :try_to_login => true)
        user if user.active?
      end
    rescue => text
      raise text
    end
  end

  def self.included(receiver)
    receiver.extend(ClassMethods)
    receiver.send(:include, InstanceMethods)

    receiver.instance_eval do
      after_create :add_to_fixed_group, :sync_fields_and_groups
      delegate :sync_on_login?, :to => :auth_source, :allow_nil => true
    end
    receiver.class_eval do
      class << self
        alias_method_chain :try_to_login, :ldap_sync
      end
    end
  end
end