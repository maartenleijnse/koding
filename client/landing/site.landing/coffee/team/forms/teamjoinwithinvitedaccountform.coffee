JView           = require './../../core/jview'
TeamJoinTabForm = require './../forms/teamjointabform'

module.exports = class TeamJoinWithInvitedAccountForm extends TeamJoinTabForm

  constructor: ->

    super

    teamData     = KD.utils.getTeamData()

    @username = new KDInputView
      placeholder      : 'pick a username'
      name             : 'username'
      defaultValue     : teamData.signup.username

    @password   = @getPassword()
    @tfcode     = @getTFCode()
    @button     = @getButton 'Done!'
    @buttonLink = @getButtonLink "Not you? <a href='#'>Create an account!</a>", (event) =>
      KD.utils.stopDOMEvent event
      return  unless event.target.tagName is 'A'
      # @emit 'FormNeedsToBeChanged', yes, yes
      @emit 'FormNeedsToBeChanged', no, no


  submit: (formData) ->

    teamData = KD.utils.getTeamData()
    teamData.signup.alreadyMember = yes

    super formData


  pistachio: ->

      """
      <div class='login-input-view hidden'><span>Password</span>{{> @username}}</div>
      <div class='login-input-view'><span>Password</span>{{> @password}}</div>
      <div class='login-input-view two-factor hidden'><span>2-factor</span>{{> @tfcode}}</div>
      <p class='dim'>
        Your email address indicates that you're already a Koding user,
        please type your password to proceed.<br>
        <a href='//#{KD.utils.getMainDomain()}/Recover' target='_self'>Forgot your password?</a>
      </p>
      <div class='TeamsModal-button-separator'></div>
      {{> @button}}
      {{> @buttonLink}}
      """
