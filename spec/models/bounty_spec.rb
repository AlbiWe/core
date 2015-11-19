# == Schema Information
#
# Table name: bounties
#
#  id                :integer          not null, primary key
#  amount            :decimal(10, 2)   not null
#  person_id         :integer
#  issue_id          :integer          not null
#  status            :string(12)       default("active"), not null
#  expires_at        :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  paid_at           :datetime
#  anonymous         :boolean          default(FALSE), not null
#  owner_type        :string(255)
#  owner_id          :integer
#  bounty_expiration :string(255)
#  upon_expiration   :string(255)
#  promotion         :string(255)
#  acknowledged_at   :datetime
#  tweet             :boolean          default(FALSE), not null
#  featured          :boolean          default(FALSE), not null
#
# Indexes
#
#  index_bounties_on_anonymous        (anonymous)
#  index_bounties_on_github_issue_id  (issue_id)
#  index_bounties_on_owner_id         (owner_id)
#  index_bounties_on_owner_type       (owner_type)
#  index_bounties_on_patron_id        (person_id)
#  index_bounties_on_status           (status)
#

require 'spec_helper'

describe Bounty do

  #backer = Person.new first_name: 'A', last_name: 'Backer'
  #issue = Github::Issue.new
  #bounty = Bounty.new backer: backer
  #google_checkout_account = Account::GoogleCheckout.first
  #backer.account.fund(1000) #
  let!(:repository) { create(:github_repository_with_issues) }
  let(:github_issue) { Github::Issue.first }
  let(:person) { create(:person) }

  it "should validate correctly" do
    bounty = Bounty.new amount: 5, issue: github_issue, person: person
    bounty.valid?.should be_truthy

    bounty = Bounty.new amount: 5.50, issue: github_issue, person: person
    bounty.valid?.should be_truthy
  end

  it "should clean up amount & display human-readable amount" do
    bounty = Bounty.new amount: 0, issue: github_issue, person: person
    bounty.valid?.should be_falsey
    bounty = Bounty.new amount: 1, issue: github_issue, person: person
    bounty.display_amount.should == '$1.00'
    bounty.valid?.should be_falsey
    bounty = Bounty.new amount: 5, issue: github_issue, person: person
    bounty.display_amount.should == '$5.00'
    bounty.valid?.should be_truthy
    bounty = Bounty.new amount: 6, issue: github_issue, person: person
    bounty.display_amount.should == '$6.00'
    bounty = Bounty.new amount: '10', issue: github_issue, person: person
    bounty.display_amount.should == '$10.00'
    bounty.amount = '5,000'
    bounty.display_amount.should == '$5000.00'
  end

  #it "should have a default expiry of six months" do
  #  bounty = Bounty.new amount: 1
  #  bounty.expires_at.should be_within(1.day).of(6.months.from_now)
  #end

  context "statistics" do
    before(:each) do
      # $45 4 days ago, $35 3 days ago, ... Each bounty has its own issue & backer
      5.times do |n|
        time_back = n.days.ago + 10.seconds # 10s to avoid date boundaries
        create(:bounty, status: 'paid', amount: (5 + n * 10), paid_at: time_back)
      end

      people = Person.first(3)  # Reuse the backers
      3.times do |n|
        create(:bounty, amount: (7 + n * 10), person: people[n],
                           expires_at: (4+n*4).days.from_now)
      end
    end

    it "should calculate $ paid since some date or ever" do
      Bounty.paid.count.should == 5
      Bounty.amount_paid_since(6.days.ago).to_f.should == 45 + 35 + 25 + 15 + 5
      Bounty.amount_paid_since(3.days.ago).to_f.should ==      35 + 25 + 15 + 5
      Bounty.amount_paid_since(1.day.ago).to_f.should  ==                15 + 5
      Bounty.amount_paid_to_date.to_f.should           == 45 + 35 + 25 + 15 + 5
    end

    it "should calculate it $ waiting to be claimed" do
      Bounty.active.count.should == 3
      Bounty.amount_unclaimed.to_f.should == 7 + 17 + 27
    end

    it "should calculate # of unique backers" do
      # TODO: figure out why this breaks intermittently
      #Person.distinct_backers_count.should == 5
    end

    it "should calculate Featured" do

    end

    it "should calculate Popular" do

    end

    it "should calculate Most Worked On" do

    end

    it "should calculate issues with the largest Bounties" do
      big = Bounty.issues_with_largest_bounties.first(2)
      big[0][1].to_i.should == 45
      big[1][1].to_i.should == 35
    end

  end

  describe "notifications" do
    let!(:issue) { create(:issue, can_add_bounty: false) }
    let!(:developer) { create(:person, first_name: 'Linus', last_name: 'Torvalds') }
    let!(:bounty_claim) { create(:bounty_claim, issue: issue, person: developer) }
    let!(:backer) { create(:person_with_money_in_account, first_name: 'Backer', last_name: 'McAwesometown', money_amount: 1337) }

    it "should email backers when a new bounty is added" do
      issue.bounties.create(person: backer, amount: 1337)
      issue.backers.should include backer
      issue.backers.each { |backer| backer.stub(:send_email).with(:bounty_increased, issue: issue).exactly(1).times }
    end

    it "should not email person twice if they are a backer and developer" do
      issue.bounties.create(person: developer, amount: 1337)
      issue.backers.should include developer
      issue.developers.should include developer
      developer.stub(:send_email).with(:bounty_increased, issue: issue).exactly(1).times
    end
  end

  describe "account" do
    let!(:issue) { create(:issue) }
    let!(:backer) { create(:person_with_money_in_account, money_amount: 100) }

    it "should not have account after create" do
      lambda {
        create(:issue)
      }.should_not change(Account, :count)
    end

    it "should not lazy load account" do
      lambda {
        issue.account
      }.should_not change(Account, :count)
    end

    it "should create account on transaction" do
      issue.account.should be_nil

      lambda {
        create_bounty(100, issue: issue, person: backer)
      }.should change(issue.transactions, :count).by 1

      issue.reload.account.should be_an Account::IssueAccount
    end

    describe "with account" do
      let!(:bounty) do
        create_bounty(100, issue: issue, person: backer)
      end

      it "should establish relationship to account" do
        issue.account.should_not be_nil
        issue.account.should be_an Account::IssueAccount
      end
    end
  end

  describe "refund" do
    let(:issue) { create(:issue) }
    let(:team_issue) { create(:issue) }
    let(:backer) { create(:person) }
    let(:team) { create(:team) }
    let!(:bounty) { create(:bounty, amount: 100, issue: issue, person: backer) }
    let(:team_bounty)  { create(:bounty, amount: 100, issue: team_issue, owner: team)}

    it "should not refund unless status is active" do
      bounty.status = Bounty::Status::REFUNDED
      bounty.should_not be_refundable

      lambda {
        bounty.refund!
      }.should_not change(Transaction, :count)
    end

    #it "should not refund if there is a solution in dispute period" do
    #  solution = create(:merged_solution, issue: issue)
    #  solution.should be_in_dispute_period
    #  issue.solutions.in_dispute_period.should include solution
    #  bounty.should_not be_refundable
    #
    #  lambda {
    #    bounty.refund!
    #  }.should_not change(Transaction, :count)
    #end

    #it "should not refund is there is a disputed, unrejected solution" do
    #  solution = create(:merged_solution, issue: issue, disputed: 1, rejected: 0)
    #  solution.should be_disputed
    #  bounty.should_not be_refundable
    #
    #  lambda {
    #    bounty.refund!
    #  }.should_not change(Transaction, :count)
    #end

    it "should refund" do
      lambda {
        bounty.refund!
      }.should change(Transaction, :count).by 1
    end

    it "should refund a team bounty" do
      lambda {
        team_bounty.refund!
      }.should change(Transaction, :count).by 1
    end

    it "should get the splits right when owned by a person" do
      bounty.refund!

      transaction = Transaction.last

      # pp transaction.splits

      # should have split taking money from issue account
      transaction.splits.select { |s| s.amount == -bounty.amount && s.item == issue }.should be_present

      # should have split putting money into backer's account
      transaction.splits.select { |s| s.amount == +bounty.amount && s.item == backer }.should be_present
    end

    it "should change issue account balance" do
      lambda {
        bounty.refund!
        issue.reload
      }.should change(issue, :account_balance).by -bounty.amount
    end

    it "should change person account balance" do
      lambda {
        bounty.refund!
        backer.reload
      }.should change(backer, :account_balance).by +bounty.amount
    end

    it "should update bounty to refunded status" do
      lambda {
        bounty.refund!
        bounty.reload
      }.should change(bounty, :status).to Bounty::Status::REFUNDED
    end

    it "should update displayed issue bounty total" do
      bounty.refund!
      issue.reload.bounty_total.should be == 0
    end

    it "should email backer" do
      backer.should_receive(:send_email).with(:bounty_refunded, bounty: bounty, transaction: kind_of(Transaction)).once
      bounty.refund!
    end

    context "when bounty is owned by a team" do
      it "should create accurate splits" do
        team_bounty.refund!

        transaction = Transaction.last

        # should have split taking money from issue account
        transaction.splits.select { |s| s.amount == -team_bounty.amount && s.item == team_issue }.should be_present
        # should have split putting money into backer's account
        transaction.splits.select { |s| s.amount == +team_bounty.amount && s.item == team }.should be_present
      end

      it "should change team account balance" do
       lambda {
          team_bounty.refund!
          team.reload
        }.should change(team, :account_balance).by +team_bounty.amount
      end
    end
  end

  describe "displayed bounty total" do
    let(:issue) { create(:issue) }

    it "should be 0" do
      issue.bounty_total.should be == 0
    end

    it "should still be 0" do
      issue.update_bounty_total
      issue.bounty_total.should be == 0
    end

    it "should trigger bounty_total update" do
      issue.should_receive(:update_bounty_total).once
      create_bounty(100, issue: issue)
    end
  end

  describe '#after_purchase' do
    shared_examples_for 'a checkout method' do
      let(:pledge) { create(:pledge) }
      let(:order) { create(:transaction) }

      it 'should not overwrite owner' do
        person = create(:person)
        pledge.owner = person
        expect { pledge.after_purchase(order) }.not_to(change(pledge, :owner))
      end
    end

    describe 'Team Account' do
      let(:team) { create(:team) }
      let(:checkout_method) { Account::Team.instance }
      it_behaves_like 'a checkout method'
    end
  end
end
