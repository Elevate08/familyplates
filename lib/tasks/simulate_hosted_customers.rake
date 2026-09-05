namespace :hosted do
  desc "Simulate 100 realistic customers using test Stripe connection and hosted model data"
  task simulate_customers: :environment do
    require "securerandom"
    require "concurrent"

    puts "🚀 Starting 100-Customer Simulation for Hosted FamilyPlates..."
    start_time = Time.current

    # Ensure Stripe connection
    stripe_key = ENV["STRIPE_SECRET_KEY"].presence || ENV["STRIPE_PRIVATE_KEY"].presence
    unless stripe_key
      abort "❌ Error: Stripe test key not configured in ENV['STRIPE_SECRET_KEY'] or ENV['STRIPE_PRIVATE_KEY']"
    end
    Stripe.api_key = stripe_key

    # Seed Promotion Programs
    puts "\n🎟️  Seeding Promotion Programs..."
    promotions = {
      "WELCOME20" => { name: "Welcome Promo (20% Off)", discount_percent: 20, active: true, notes: "New sign-up discount" },
      "ANNUAL50"  => { name: "Annual Saver Special (50% Off First Year)", discount_percent: 50, active: true, notes: "Best value promo" },
      "FAMILY2025"=> { name: "Family Kitchen Pass (25% Off)", discount_percent: 25, active: true, notes: "Spring campaign promo" },
      "BETA100"   => { name: "Early Beta Supporter (100% Lifetime)", discount_percent: 100, active: true, notes: "Founding tester program" },
      "HOLIDAY30" => { name: "Holiday Feast Special (30% Off)", discount_percent: 30, active: false, ends_at: 6.months.ago, notes: "Expired campaign" }
    }

    promo_records = {}
    promotions.each do |code, attrs|
      prog = PromotionProgram.find_or_initialize_by(code: code)
      prog.assign_attributes(attrs)
      prog.save!
      promo_records[code] = prog
      puts "   • #{code}: #{prog.name} (#{prog.active? ? 'Active' : 'Inactive'})"
    end

    # Surnames and Kitchen Names for 100 realistic households
    family_names = [
      "Miller", "Anderson", "Chen", "Rivera", "O'Connor", "Patel", "Tanaka", "Watanabe",
      "Hernandez", "Smith", "Dupont", "Garcia", "Kim", "Rossi", "Larsson", "Murphy",
      "Kowalski", "Santos", "Novak", "Fischer", "Nielsen", "Dubois", "Moreau", "Conti",
      "Silva", "Alvarez", "Gomez", "Taylor", "Wilson", "Brown", "Davies", "Evans",
      "Thomas", "Roberts", "Johnson", "Williams", "Jones", "Jackson", "White", "Harris",
      "Martin", "Thompson", "Martinez", "Robinson", "Clark", "Rodriguez", "Lewis", "Lee",
      "Walker", "Hall", "Allen", "Young", "King", "Wright", "Scott", "Torres",
      "Nguyen", "Hill", "Flores", "Green", "Adams", "Nelson", "Baker", "Hall",
      "Campbell", "Mitchell", "Carter", "Roberts", "Phillips", "Evans", "Turner", "Diaz",
      "Parker", "Cruz", "Edwards", "Collins", "Reyes", "Stewart", "Morris", "Morales",
      "Sanchez", "Kimura", "Sato", "Suzuki", "Takahashi", "Ito", "Nakamura", "Kobayashi",
      "Yamamoto", "Saito", "Kato", "Yoshida", "Yamada", "Sasaki", "Yamaguchi", "Matsumoto",
      "Inoue", "Kimura", "Hayashi", "Shimizu"
    ]

    recipe_templates = [
      { name: "Sheet Pan Honey-Mustard Salmon", prep: 10, cook: 20, tags: "dinner, quick, seafood", meal_types: "dinner" },
      { name: "Classic Beef Bolognese with Rigatoni", prep: 15, cook: 45, tags: "dinner, pasta, comfort", meal_types: "dinner" },
      { name: "Crispy Black Bean Tacos", prep: 10, cook: 15, tags: "dinner, vegetarian, quick", meal_types: "dinner" },
      { name: "Greek Lemon Herb Chicken & Potatoes", prep: 15, cook: 40, tags: "dinner, chicken, mediterranean", meal_types: "dinner" },
      { name: "Weekend Fluffy Buttermilk Pancakes", prep: 10, cook: 15, tags: "breakfast, kid-friendly", meal_types: "breakfast" },
      { name: "Sesame Ginger Vegetable Soba Bowl", prep: 15, cook: 10, tags: "lunch, vegetarian, healthy", meal_types: "lunch" },
      { name: "Slow Cooker Smoky Turkey Chili", prep: 20, cook: 240, tags: "dinner, slow-cooker, meal-prep", meal_types: "dinner" },
      { name: "Avocado & Soft Boiled Egg Toast", prep: 5, cook: 8, tags: "breakfast, quick", meal_types: "breakfast" }
    ]

    pantry_staples = [
      { name: "Olive Oil", cat: "Oils & Vinegars", emoji: "oil-bottle" },
      { name: "Black Pepper", cat: "Spices & Seasonings", emoji: "pepper-shaker" },
      { name: "Granulated Sugar", cat: "Baking", emoji: "sugar-bag" },
      { name: "Garlic Powder", cat: "Spices & Seasonings", emoji: "spice-jar" },
      { name: "Kosher Salt", cat: "Spices & Seasonings", emoji: "🧂" },
      { name: "Soy Sauce", cat: "Condiments & Sauces", emoji: "🥢" },
      { name: "Jasmine Rice", cat: "Grains & Pasta", emoji: "🍚" },
      { name: "Rigatoni Pasta", cat: "Grains & Pasta", emoji: "🍝" },
      { name: "Eggs", cat: "Dairy & Eggs", emoji: "🥚" },
      { name: "Butter", cat: "Dairy & Eggs", emoji: "🧈" }
    ]

    # Pre-define 100 simulation customer specs covering EVERY case
    specs = []

    # 1. Active Annual Customers (25)
    # Long-term memberships created across last year (Sep 2025 - Jul 2026)
    25.times do |i|
      created_ago = (1..12).to_a[i % 12].months + (1..20).to_a[i % 20].days
      promo = case i
              when 0..4 then "ANNUAL50"
              when 5..7 then "WELCOME20"
              else nil
              end
      specs << {
        cohort: :active_annual,
        plan: :annual,
        status: "active",
        created_ago: created_ago,
        sub_period_start_ago: (created_ago > 1.year ? created_ago - 1.year : created_ago),
        sub_period_end_future: 1.year - (created_ago > 1.year ? created_ago - 1.year : created_ago),
        promo: promo,
        suspended: false
      }
    end

    # 2. Active Monthly Customers (30)
    # Created 1 to 12 months ago with regular monthly billing cycles
    30.times do |i|
      created_ago = (1..12).to_a[i % 12].months + (2..25).to_a[i % 24].days
      cycle_day = (1..26).to_a[i % 26]
      promo = case i
              when 0..4 then "FAMILY2025"
              when 5..8 then "WELCOME20"
              when 9 then "BETA100"
              else nil
              end
      specs << {
        cohort: :active_monthly,
        plan: :monthly,
        status: "active",
        created_ago: created_ago,
        sub_period_start_ago: cycle_day.days,
        sub_period_end_future: (30 - cycle_day).days,
        promo: promo,
        suspended: false
      }
    end

    # 3. Active Free Trials (12)
    # Joined 1 to 13 days ago
    12.times do |i|
      created_ago = (i + 1).days + rand(2..18).hours
      promo = (i < 3) ? "WELCOME20" : nil
      specs << {
        cohort: :trialing,
        plan: nil,
        status: "trialing",
        created_ago: created_ago,
        promo: promo,
        suspended: false
      }
    end

    # 4. Expired Free Trials (12)
    # Joined 1 to 9 months ago, never subscribed
    12.times do |i|
      created_ago = (1..9).to_a[i % 9].months + (3..20).to_a[i % 18].days
      specs << {
        cohort: :expired_trial,
        plan: nil,
        status: "expired",
        created_ago: created_ago,
        promo: nil,
        suspended: false
      }
    end

    # 5. Past Due - Within Grace Period (4)
    # Active monthly whose renewal payment failed 2-5 days ago (within 7-day grace period)
    4.times do |i|
      created_ago = (3..7).to_a[i].months
      failed_ago = (2 + i).days
      specs << {
        cohort: :past_due_grace,
        plan: :monthly,
        status: "past_due",
        created_ago: created_ago,
        sub_period_start_ago: (30 + failed_ago),
        sub_period_end_ago: failed_ago,
        promo: (i == 0 ? "FAMILY2025" : nil),
        suspended: false
      }
    end

    # 6. Past Due - Grace Expired (4)
    # Payment failed 15-30 days ago, past grace period
    4.times do |i|
      created_ago = (4..8).to_a[i].months
      failed_ago = (14 + i * 4).days
      specs << {
        cohort: :past_due_expired,
        plan: :monthly,
        status: "past_due",
        created_ago: created_ago,
        sub_period_start_ago: (30 + failed_ago),
        sub_period_end_ago: failed_ago,
        promo: nil,
        suspended: false
      }
    end

    # 7. Canceled - Retaining Access (4)
    # Canceled recently, retains access until end of current period
    4.times do |i|
      created_ago = (2..5).to_a[i].months
      ends_in = (6 + i * 5).days
      specs << {
        cohort: :canceled_retaining,
        plan: :monthly,
        status: "active",
        created_ago: created_ago,
        sub_period_start_ago: (30 - ends_in),
        ends_at_future: ends_in,
        promo: nil,
        suspended: false
      }
    end

    # 8. Canceled - Expired (5)
    # Canceled months ago, access ended
    5.times do |i|
      created_ago = (6..11).to_a[i].months
      ended_ago = (1..3).to_a[i % 3].months
      specs << {
        cohort: :canceled_expired,
        plan: :monthly,
        status: "canceled",
        created_ago: created_ago,
        sub_period_start_ago: ended_ago + 30.days,
        ends_at_ago: ended_ago,
        promo: nil,
        suspended: false
      }
    end

    # 9. Suspended by Operator (3)
    [
      { reason: "Suspected fraudulent chargeback dispute", plan: :annual, status: "active", created_ago: 8.months },
      { reason: "Terms of service: Automated scraping & spam", plan: :monthly, status: "past_due", created_ago: 4.months },
      { reason: "Customer requested temporary administrative account hold", plan: nil, status: "trialing", created_ago: 5.days }
    ].each do |susp_spec|
      specs << {
        cohort: :suspended,
        plan: susp_spec[:plan],
        status: susp_spec[:status],
        created_ago: susp_spec[:created_ago],
        promo: nil,
        suspended: true,
        suspension_reason: susp_spec[:reason]
      }
    end

    # 10. Account Deletion Pending (1)
    specs << {
      cohort: :deletion_pending,
      plan: :monthly,
      status: "active",
      created_ago: 6.months,
      sub_period_start_ago: 10.days,
      sub_period_end_future: 20.days,
      promo: "WELCOME20",
      suspended: false,
      deletion_pending: true
    }

    puts "\n📦 Prepared #{specs.size} customer specifications."

    # Concurrent Stripe Customer Creation
    puts "\n⚡ Connecting to Stripe Test API to create 100 test customer objects..."
    stripe_customers = Array.new(specs.size)
    pool = Concurrent::FixedThreadPool.new(8)

    specs.each_with_index do |spec, idx|
      pool.post do
        surname = family_names[idx % family_names.size]
        household_name = (idx % 3 == 0) ? "The #{surname} Family" : ((idx % 3 == 1) ? "#{surname} Kitchen" : "The #{surname}s")
        email = "sim_customer_#{idx + 1}@example.com"

        begin
          customer_params = {
            name: household_name,
            email: email,
            description: "FamilyPlates Simulation Customer ##{idx + 1} (#{spec[:cohort]})",
            metadata: {
              simulation: "true",
              cohort: spec[:cohort].to_s,
              plan: spec[:plan].to_s
            }
          }
          customer_params[:source] = "tok_visa" if spec[:plan].present?

          stripe_customer = Stripe::Customer.create(customer_params)
          stripe_customers[idx] = stripe_customer
          print "." if (idx + 1) % 10 == 0
        rescue => e
          puts "\n⚠️ Stripe creation note for ##{idx + 1}: #{e.message}. Using synthetic processor ID."
          stripe_customers[idx] = OpenStruct.new(id: "cus_sim_#{SecureRandom.hex(10)}")
        end
      end
    end

    pool.shutdown
    pool.wait_for_termination

    puts "\n✅ Stripe test customer objects provisioned."

    # Now populate database records
    puts "\n🏠 Inserting Households, Family Members, Subscriptions, and Kitchen Data..."

    ActiveRecord::Base.transaction do
      specs.each_with_index do |spec, idx|
        surname = family_names[idx % family_names.size]
        household_name = (idx % 3 == 0) ? "The #{surname} Family" : ((idx % 3 == 1) ? "#{surname} Kitchen" : "The #{surname}s")
        email = "sim_customer_#{idx + 1}@example.com"
        created_at = Time.current - spec[:created_ago]
        stripe_customer = stripe_customers[idx]

        # 1. Household
        household = Household.find_or_initialize_by(id: "sim-house-#{idx + 1}")
        household.name = household_name
        household.join_code ||= SecureRandom.alphanumeric(12).upcase.scan(/.{4}/).join("-")
        household.created_at = created_at
        household.updated_at = [created_at + 1.hour, Time.current].min
        household.onboarded_at = created_at + 15.minutes
        household.promotion_code = spec[:promo]
        household.breakfast_time = "07:30"
        household.lunch_time = "12:00"
        household.dinner_time = "18:30"

        if spec[:suspended]
          household.suspended_at = 2.weeks.ago
          household.suspension_reason = spec[:suspension_reason]
        else
          household.suspended_at = nil
          household.suspension_reason = nil
        end

        household.save!(validate: false)

        # 2. User & Family Members
        user = User.find_or_initialize_by(email: email)
        user.password = "CustomerPassword123!"
        user.created_at = created_at
        user.save!(validate: false)

        admin_member = household.family_members.find_or_initialize_by(name: "#{surname} Head")
        admin_member.user = user
        admin_member.role = "admin"
        admin_member.avatar_color = "#ea580c"
        admin_member.created_at = created_at
        admin_member.save!(validate: false)

        # Additional family member (e.g. partner or kid)
        if idx % 2 == 0
          member2 = household.family_members.find_or_initialize_by(name: "Alex #{surname}")
          member2.role = "member"
          member2.avatar_color = "#0284c7"
          member2.created_at = created_at + 1.day
          member2.save!(validate: false)
        end

        # 3. Pay Customer & Subscription
        if stripe_customer&.id.present?
          pay_cust = household.pay_customers.find_or_initialize_by(processor: :stripe)
          pay_cust.processor_id = stripe_customer.id
          pay_cust.default = true
          pay_cust.created_at = created_at
          pay_cust.save!(validate: false)

          if spec[:plan].present?
            plan_key = spec[:plan]
            plan_name = plan_key == :annual ? "Annual" : "Monthly"
            plan_id = plan_key == :annual ? "price_annual" : "price_monthly"

            sub = pay_cust.subscriptions.find_or_initialize_by(name: "default")
            sub.processor_id = "sub_sim_#{SecureRandom.hex(10)}"
            sub.processor_plan = plan_id
            sub.quantity = 1
            sub.status = spec[:status]
            sub.type = "Pay::Stripe::Subscription"
            sub.created_at = created_at

            if spec[:promo].present?
              sub.metadata = { "promotion_code" => spec[:promo] }
              sub.data = { "promotion_code" => spec[:promo], "discount" => { "promotion_code" => spec[:promo] } }
            end

            # Period calculations
            if spec[:sub_period_start_ago].present?
              sub.current_period_start = Time.current - spec[:sub_period_start_ago]
            else
              sub.current_period_start = created_at
            end

            if spec[:sub_period_end_future].present?
              sub.current_period_end = Time.current + spec[:sub_period_end_future]
            elsif spec[:sub_period_end_ago].present?
              sub.current_period_end = Time.current - spec[:sub_period_end_ago]
            else
              sub.current_period_end = sub.current_period_start + (plan_key == :annual ? 1.year : 1.month)
            end

            if spec[:ends_at_future].present?
              sub.ends_at = Time.current + spec[:ends_at_future]
            elsif spec[:ends_at_ago].present?
              sub.ends_at = Time.current - spec[:ends_at_ago]
            end

            sub.save!(validate: false)

            # Record Pay Charge & Live Stripe Transactions for customers
            if sub.status == "active" || spec[:cohort] == :past_due_grace
              amount_cents = if plan_key == :annual
                case spec[:promo]
                when "ANNUAL50" then 1750
                when "WELCOME20" then 2800
                else 3500
                end
              else
                case spec[:promo]
                when "WELCOME20" then 320
                when "FAMILY2025" then 300
                when "BETA100" then 0
                else 400
                end
              end

              real_charge = nil
              if amount_cents > 0 && stripe_customer&.id.to_s.start_with?("cus_")
                begin
                  real_charge = Stripe::Charge.create(
                    amount: amount_cents,
                    currency: "usd",
                    customer: stripe_customer.id,
                    description: "FamilyPlates #{plan_name} Plan - #{household_name}",
                    metadata: {
                      household_id: household.id,
                      cohort: spec[:cohort].to_s,
                      plan: plan_key.to_s,
                      promo: spec[:promo].to_s
                    }
                  )
                rescue => e
                  # Fallback if card rate limit or token error
                end
              end

              charge_id = real_charge&.id || "ch_sim_#{SecureRandom.hex(10)}"
              charge = pay_cust.charges.find_or_initialize_by(processor_id: charge_id)
              charge.subscription = sub
              charge.amount = amount_cents
              charge.currency = "usd"
              charge.type = "Pay::Stripe::Charge"
              charge.created_at = sub.current_period_start
              charge.data = {
                "brand" => "visa",
                "last4" => "4242",
                "receipt_url" => real_charge&.receipt_url,
                "paid" => true
              }
              charge.save!(validate: false)

              # For established monthly customers, record prior renewal cycle charges
              months_active = [((Time.current - created_at) / 30.days).floor, 1].max
              if months_active > 1 && spec[:cohort] == :active_monthly
                (1...[months_active, 6].min).each do |m|
                  hist_charge = pay_cust.charges.find_or_initialize_by(processor_id: "ch_hist_#{sub.id}_#{m}")
                  hist_charge.subscription = sub
                  hist_charge.amount = amount_cents
                  hist_charge.currency = "usd"
                  hist_charge.type = "Pay::Stripe::Charge"
                  hist_charge.created_at = sub.current_period_start - m.months
                  hist_charge.data = { "brand" => "visa", "last4" => "4242", "paid" => true }
                  hist_charge.save!(validate: false)
                end
              end
            end
          end
        end

        # Track promotion program redemptions
        if spec[:promo].present? && promo_records[spec[:promo]]
          promo_records[spec[:promo]].increment!(:redeemed_count)
        end

        # 4. Sample Recipes & Pantry
        recipe_pick = recipe_templates[idx % recipe_templates.size]
        recipe = household.recipes.find_or_initialize_by(title: recipe_pick[:name])
        recipe.prep_time = recipe_pick[:prep]
        recipe.cook_time = recipe_pick[:cook]
        recipe.total_time = recipe_pick[:prep] + recipe_pick[:cook]
        recipe.instructions = "1. Prepare fresh ingredients.\n2. Cook with care and seasonings.\n3. Serve warm and enjoy!"
        recipe.tags = recipe_pick[:tags]
        recipe.meal_types = recipe_pick[:meal_types]
        recipe.servings = 4
        recipe.created_at = created_at + 1.hour
        recipe.save!(validate: false)

        # Pantry Items
        pantry_staples.take(4).each do |staple|
          pantry = household.pantry_items.find_or_initialize_by(name: staple[:name])
          pantry.aisle_category = staple[:cat]
          pantry.emoji = staple[:emoji]
          pantry.created_at = created_at + 2.hours
          pantry.save!(validate: false)
        end

        # 5. Activity Events
        household.activity_events.create!(
          event_type: "recipes.created",
          actor: admin_member,
          source: "web",
          target_type: "Recipe",
          target_id: recipe.id.to_s,
          metadata: { "target_name" => recipe.title },
          created_at: created_at + 1.hour
        )

        if spec[:plan].present?
          household.activity_events.create!(
            event_type: "subscriptions.created",
            actor: admin_member,
            source: "web",
            metadata: { "target_name" => "#{spec[:plan].to_s.titleize} Plan" },
            created_at: created_at + 2.hours
          )
        end

        # 6. Support Thread for a subset of customers (8 households)
        if idx % 12 == 0
          thread = household.support_threads.find_or_initialize_by(subject: "Question regarding billing receipt and features")
          thread.created_by_user_id = user.id
          thread.status = (idx % 24 == 0) ? "open" : "resolved"
          thread.last_message_at = created_at + 3.days
          thread.resolved_at = (thread.status == "resolved" ? created_at + 3.days + 4.hours : nil)
          thread.created_at = created_at + 3.days
          thread.save!(validate: false)

          thread.messages.find_or_create_by!(
            user_id: user.id,
            body: "Hi team, loving FamilyPlates so far! Could you please let us know where to find annual billing VAT invoices?",
            created_at: thread.created_at
          )

          if thread.status == "resolved"
            operator = PlatformAdminAccount.find_by(email: "operator@familyplates.local") || PlatformAdminAccount.first
            thread.messages.find_or_create_by!(
              platform_admin: operator,
              body: "Hello! You can view and download all past billing invoices directly in your account billing portal. Let us know if you need anything else!",
              created_at: thread.created_at + 4.hours
            )
          end
        end

        # 7. Account Deletion Request
        if spec[:deletion_pending]
          req = household.account_deletion_requests.find_or_initialize_by(status: "pending")
          req.requested_by_user_id = user.id
          req.requested_at = 2.days.ago
          req.created_at = 2.days.ago
          req.save!(validate: false)
        end
      end
    end

    elapsed = (Time.current - start_time).round(2)
    puts "\n🎉 Successfully simulated 100 customers in #{elapsed}s!"
    puts "📊 Summary in Database:"
    puts "   • Households: #{Household.count}"
    puts "   • Active Subscriptions: #{Household.all.count(&:active_subscription?)}"
    puts "   • Free Trials: #{Household.all.count { |h| h.subscription_status == :trialing }}"
    puts "   • Past Due / Grace: #{Household.all.count { |h| [:past_due, :past_due_grace].include?(h.subscription_status) }}"
    puts "   • Suspended: #{Household.where.not(suspended_at: nil).count}"
    puts "   • Promotion Programs: #{PromotionProgram.count}"
    puts "   • Promo Redemptions Tracked: #{PromotionProgram.sum(:redeemed_count)}"
  end
end
