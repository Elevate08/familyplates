module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_family_member

    def connect
      set_current_family_member || reject_unauthorized_connection
    end

    private

    def set_current_family_member
      if member_id = cookies.signed[:active_family_member_id]
        self.current_family_member = FamilyMember.find_by(id: member_id)
      end
    end
  end
end
