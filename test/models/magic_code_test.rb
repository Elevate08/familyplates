require "test_helper"

class MagicCodeTest < ActiveSupport::TestCase
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  # @card-15.3
  test "generates a 6-character code and 15-minute expiry on create" do
    magic_code = MagicCode.create!(email: "  User@Example.COM ")

    assert_match UUID_PATTERN, magic_code.id
    assert_equal "user@example.com", magic_code.email
    assert_match(/\A[A-Z0-9]{6}\z/, magic_code.code)
    assert_not magic_code.expired?
    assert magic_code.expires_at > Time.current
    assert magic_code.expires_at <= 15.minutes.from_now + 5.seconds
  end

  # @card-15.5
  test "active scope excludes expired codes" do
    active = MagicCode.create!(email: "active@example.com", code: "ACT123", expires_at: 10.minutes.from_now)
    expired = MagicCode.create!(email: "expired@example.com", code: "EXP123", expires_at: 1.minute.ago)

    assert_includes MagicCode.active, active
    assert_not_includes MagicCode.active, expired
  end

  # @card-15.4
  test "for_unknown_email returns an unpersisted code" do
    fake = MagicCode.for_unknown_email("stranger@example.com")

    assert_not fake.persisted?
    assert_equal "stranger@example.com", fake.email
    assert_match(/\A[A-Z0-9]{6}\z/, fake.code)
    assert_not fake.expired?
  end

  test "issuing a new code retires prior codes for the same email" do
    old = MagicCode.create!(email: "rotate@example.com", code: "OLD123")
    fresh = MagicCode.create!(email: "rotate@example.com", code: "NEW123")

    assert_not MagicCode.exists?(old.id)
    assert MagicCode.exists?(fresh.id)
    assert_nil MagicCode.redeem(email: "rotate@example.com", code: "OLD123")
  end

  test "successful redeem consumes every code for the email" do
    MagicCode.create!(email: "ok@example.com", code: "GOOD12")

    assert MagicCode.redeem(email: "ok@example.com", code: "good12")
    assert_equal 0, MagicCode.where(email: "ok@example.com").count
  end

  # Guesses count against the code they guess at, not the address: five
  # wrong guesses retire that code, and a code requested afterwards starts
  # fresh, so nobody can keep an address locked out by guessing at it.
  test "five failed redeems retire the code; a code requested afterwards still works" do
    MagicCode.create!(email: "guess@example.com", code: "REAL22")

    5.times do
      assert_nil MagicCode.redeem(email: "guess@example.com", code: "WRONG2")
    end

    assert_equal 0, MagicCode.where(email: "guess@example.com").count
    assert_nil MagicCode.redeem(email: "guess@example.com", code: "REAL22")

    MagicCode.create!(email: "guess@example.com", code: "LATER2")
    assert MagicCode.redeem(email: "guess@example.com", code: "LATER2")
  end

  # Every attempt is counted before it is compared, so a burst of parallel
  # guesses cannot all be checked against the live code before any of them
  # is counted. Here the store reports that five attempts are already in.
  test "an attempt beyond the limit is refused even when it is the right code" do
    MagicCode.create!(email: "burst@example.com", code: "REAL22")
    live = MagicCode.find_by!(email: "burst@example.com")
    MagicCode.attempt_store.write(MagicCode.failure_key(live.id), MagicCode::MAX_FAILED_ATTEMPTS, expires_in: 15.minutes)

    assert_nil MagicCode.redeem(email: "burst@example.com", code: "REAL22")
    assert_not MagicCode.exists?(live.id)
  end

  test "four wrong guesses do not stop the right code" do
    MagicCode.create!(email: "guess@example.com", code: "REAL22")
    4.times { MagicCode.redeem(email: "guess@example.com", code: "WRONG2") }
    assert MagicCode.redeem(email: "guess@example.com", code: "REAL22")
  end

  test "guessing at an address with no live code counts nothing against its next code" do
    6.times { assert_nil MagicCode.redeem(email: "guess@example.com", code: "WRONG2") }
    MagicCode.create!(email: "guess@example.com", code: "FRESH2")
    assert MagicCode.redeem(email: "guess@example.com", code: "FRESH2")
  end

  test "a code consumed by another redeemer between lookup and claim yields nothing" do
    MagicCode.create!(email: "race@example.com", code: "RACE22")

    # Simulate the competing redeemer: it deletes the row right after our
    # lookup found it, before we try to claim it.
    relation = MagicCode.active
    racer = Object.new
    racer.define_singleton_method(:find_by) do |**attrs|
      found = relation.find_by(**attrs)
      MagicCode.where(id: found.id).delete_all if found
      found
    end

    original = MagicCode.method(:active)
    MagicCode.define_singleton_method(:active) { racer }
    begin
      result = MagicCode.redeem(email: "race@example.com", code: "RACE22")
    ensure
      MagicCode.define_singleton_method(:active, original)
    end

    assert_nil result
  end

  test "two concurrent redeems of the same valid code yield at most one success" do
    MagicCode.create!(email: "twice@example.com", code: "TWICE2")
    ready = Queue.new
    go = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          MagicCode.redeem(email: "twice@example.com", code: "TWICE2")
        end
      end
    end
    2.times { ready.pop }
    2.times { go << true }
    results = threads.map(&:value)

    assert_operator results.compact.size, :<=, 1
    assert_equal 1, results.compact.size
    assert_equal 0, MagicCode.where(email: "twice@example.com").count
  end
end
