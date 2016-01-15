require 'set'
require 'audited/audit'

module Audited
  module Adapters
    module ActiveRecord
      # Audit saves the changes to ActiveRecord models.  It has the following attributes:
      #
      # * <tt>auditable</tt>: the ActiveRecord model that was changed
      # * <tt>user</tt>: the user that performed the change; a string or an ActiveRecord model
      # * <tt>action</tt>: one of create, update, or delete
      # * <tt>audited_changes</tt>: a serialized hash of all the changes
      # * <tt>comment</tt>: a comment set with the audit
      # * <tt>version</tt>: the version of the model
      # * <tt>request_uuid</tt>: a uuid based that allows audits from the same controller request
      # * <tt>created_at</tt>: Time that the change was performed
      #
      
      # This version of the Audit model is specific to Club Holdings, to match the legacy version of the table that is in use.
      class Audit < ::ActiveRecord::Base
      if Rails.version >= "3.2.0"
        include Audited::Audit
        include ActiveModel::Observing
      end
        # make this Audit model work without all the new columns that the Audit gem is trying to populate
        attr_accessor :associated_id, :associated_type, :user_id, :comment, :remote_address, :request_uuid

        # belongs_to :auditable , :polymorphic => true
        # belongs_to :audit_type
        belongs_to :membership,    :foreign_key => "membership_uid"
        belongs_to :quintess_user, :class_name => "QuintessUser", :foreign_key => "quintess_editor_uid"
        belongs_to :member,        :class_name => "Member", :foreign_key => "member_editor_uid" # This association screws up the quintess_user association somehow.
        belongs_to :membership_contract, :class_name => "MembershipContract", :foreign_key => "membership_contract_uid"

      if Rails.version >= "3.2.0"
        default_scope         ->{ order(:version)}
        scope :descending,    ->{ reorder("version DESC")}
        scope :creates,       ->{ where({:action => 'create'})}
        scope :updates,       ->{ where({:action => 'update'})}
        scope :destroys,      ->{ where({:action => 'destroy'})}

        scope :up_until,      ->(date_or_time){where("created_at <= ?", date_or_time) }
        scope :from_version,  ->(version){where(['version >= ?', version]) }
        scope :to_version,    ->(version){where(['version <= ?', version]) }
        scope :auditable_finder, ->(auditable_id, auditable_type){where(auditable_id: auditable_id, auditable_type: auditable_type)}
        # Return all audits older than the current one.
        def ancestors
          self.class.where(['auditable_id = ? and auditable_type = ? and version <= ?',
            auditable_id, auditable_type, version])
        end
      end

        serialize :change_history

        before_save :cancel_if_disabled     if Rails.version >= "3.2.0"
        before_save :fill_legacy_columns
        before_save(:fill_quintess_columns) if Rails.version >= "3.2.0"

      	Rails.version >= "3.2.0" ? (self.table_name = "Audit")      : set_table_name('Audit')
      	Rails.version >= "3.2.0" ? (self.primary_key = "audit_uid") : set_primary_key('audit_uid')

        def user=(user_name)
        end

        def user
          nil
        end

        def audited_changes=(changes)
          self.change_history = changes
        end

        def audited_changes
          change_history
        end

      if Rails.version >= "3.2.0"

        def set_version_number
          # max = self.class.auditable_finder(auditable_id, auditable_type).maximum(:version) || 0
          # self.version = max + 1
          # we'll try it without versioning first.
          self.version = 0
        end
      end


        def self.these_uids(key_uid_hash = nil)
          #logger.error "Threading Audit.these_uids, key_uid_hash = #{key_uid_hash.inspect rescue 'rescue'}"

          @@foreign_keys = key_uid_hash || {}
        end

        def self.uids_columns()
          begin
            #logger.error "Threading Audit.uids_columns, @@foreign_keys = #{@@foreign_keys.inspect rescue 'rescue'}"
            logger.error("Threading Audit.uids_columns, member/membership mismatch @@foreign_keys = #{(@@foreign_keys && @@foreign_keys.inspect) rescue 'rescue'}") if @@foreign_keys && @@foreign_keys[:member_uid] && @@foreign_keys[:membership_uid] && MemberMembership.find(:first, :conditions => ['member_uid = ? AND membership_uid = ?', @@foreign_keys[:member_uid], @@foreign_keys[:membership_uid]])
          rescue
          end

          @@foreign_keys rescue @@foreign_keys = {}
        end

        def self.audited_classes
          @@audited_classes ||= find( :all, :select => "DISTINCT auditable_type", :order  => "auditable_type ASC" ).collect {|a| a.auditable_type}
        end

        def self.add_audited_class(class_name)
          unless audited_classes.detect{|ac| ac == class_name}
            audited_classes << class_name
          end
        end

        def self.disabled=(disabled_flag)
          @@disabled = disabled_flag
        end

        def self.disabled
          @@disabled rescue @@disabled = false
        end

      protected
        def fill_legacy_columns
          atu = (self.action || 'nothing').upcase
          self.audit_type_ucode = atu if %w{CREATE UPDATE DESTROY}.include?(atu)
          true
        end

      if Rails.version >= "3.2.0"
        def fill_quintess_columns
          self.member_editor_uid   = Logon.current_member,
          self.quintess_editor_uid = Logon.current_quintess_user
          true
        end

        def cancel_if_disabled
          return false if Audit.disabled
          true
        end
      end
      end

    end
  end
end
