class GroupsAppController extends AppController

  KD.registerAppClass @,
    name         : "Groups"
    route        : "/Groups"
    hiddenHandle : yes

  @privateGroupOpenHandler =(event)->
    event.preventDefault()
    @emit 'PrivateGroupIsOpened', @getData()

  [
    ERROR_UNKNOWN
    ERROR_NO_POLICY
    ERROR_APPROVAL_REQUIRED
    ERROR_PERSONAL_INVITATION_REQUIRED
    ERROR_MULTIUSE_INVITATION_REQUIRED
    ERROR_WEBHOOK_CUSTOM_FORM
    ERROR_POLICY
  ] = [403010, 403001, 403002, 403003, 403004, 403005, 403009]

  constructor:(options = {}, data)->

    options.view    = new GroupsMainView
      cssClass      : "content-page groups"
    options.appInfo =
      name          : "Groups"

    super options, data

    @listItemClass = GroupsListItemView
    @controllers   = {}
    @isReady       = no
    @getSingleton('windowController').on "FeederListViewItemCountChanged", (count, itemClass, filterName)=>
      if @_searchValue and itemClass is @listItemClass then @setCurrentViewHeader count

    @utils.defer @bound 'init'

  init:->
    mainController = @getSingleton 'mainController'
    router         = @getSingleton 'router'
    {entryPoint}   = KD.config
    mainController.on 'AccountChanged', @bound 'resetUserArea'
    mainController.on 'NavigationLinkTitleClick', (pageInfo)=>
      return unless pageInfo.path
      if pageInfo.topLevel
      then router.handleRoute "#{pageInfo.path}"
      else router.handleRoute "#{pageInfo.path}", {entryPoint}

    @groups = {}
    @currentGroupData = new GroupData

    mainController.on 'groupAccessRequested',    @showRequestAccessModal.bind this
    mainController.on 'groupJoinRequested',      @joinGroup.bind this
    mainController.on 'groupInvitationAccepted', @acceptInvitation.bind this
    mainController.on 'groupInvitationIgnored',  @ignoreInvitation.bind this
    mainController.on 'groupRequestCancelled',   @cancelGroupRequest.bind this
    mainController.on 'loginRequired',           @loginRequired.bind this

  getCurrentGroup:->
    throw 'FIXME: array should never be passed'  if Array.isArray @currentGroupData.data
    return @currentGroupData.data

  openGroupChannel:(group, callback=->)->
    @groupChannel = KD.remote.subscribe "group.#{group.slug}", {
      serviceType : 'group'
      group       : group.slug
      isExclusive : yes
      isReadOnly  : yes
    }
    # TEMP SY: to be able to work in a vagrantless env
    # to avoid shared authworker's message getting lost
    if location.hostname is "localhost"
    then do callback
    else @groupChannel.once 'setSecretName', callback

  changeGroup:(groupName='koding', callback=->)->
    return callback()  if @currentGroupName is groupName
    throw new Error 'Cannot change the group!'  if @currentGroupName?
    unless @currentGroupName is groupName
      KD.remote.cacheable groupName, (err, models)=>
        if err then callback err
        else if models?
          [group] = models
          if group.bongo_.constructorName isnt 'JGroup'
            @isReady = yes
          else
            @setGroup groupName
            @currentGroupData.setGroup group
            @openGroupChannel group, =>
              @isReady = yes
              callback null, groupName, group
              @emit 'GroupChanged', groupName, group

  getUserArea:-> @userArea

  setUserArea:(userArea)->
    @emit 'UserAreaChanged', userArea  if not _.isEqual userArea, @userArea
    @userArea = userArea

  getGroupSlug:-> @currentGroupName

  setGroup:(groupName)->
    @currentGroupName = groupName
    @setUserArea {
      group: groupName, user: KD.whoami().profile.nickname
    }

  resetUserArea:(account)->
    @setUserArea {
      group: @currentGroupName ? 'koding', user: account.profile.nickname
    }

  createFeed:(view, loadFeed = no)->

    onboardingText =
      """
        <h3 class='title'>Koding groups is a simple way to connect and interact with people who share
        your interests.</h3>

        <p>When you join a group such as your univeristy or your company, you can share virtual
        machines, collaborate on projects and stay up to date on the activites of others in your
        group.</p>

        <h3 class='title'>Easy to get started</h3>

        <p>Groups are free to create. You decide who can join, what actions they can do inside the
        group and what they see.</p>
      """

    KD.getSingleton("appManager").tell 'Feeder', 'createContentFeedController', {
      itemClass             : @listItemClass
      limitPerPage          : 20
      useHeaderNav          : yes
      listCssClass          : "groups"
      help                  :
        subtitle            : "Learn About Groups"
        tooltip             :
          title             : "<p class=\"bigtwipsy\">Groups are the basic unit of Koding society.</p>"
          placement         : "above"
      onboarding            :
        everything          : onboardingText
        mine                : onboardingText
      filter                :
        everything          :
          title             : "All groups"
          optional_title    : if @_searchValue then "<span class='optional_title'></span>" else null
          dataSource        : (selector, options, callback)=>
            {JGroup} = KD.remote.api
            if @_searchValue
              @setCurrentViewHeader "Searching for <strong>#{@_searchValue}</strong>..."
              JGroup.byRelevance @_searchValue, options, (err, items, rest...)=>
                callback err, items, rest...
                # to trigger dataEnd
                unless err
                  ids = item.getId?() for item in items
                  callback null, null, ids
            else
              JGroup.streamModels selector, options, callback
          dataEnd           :({resultsController}, ids)=>
            {everything} = resultsController.listControllers
            @markGroupRelationship everything, ids
          dataError         :(controller, err)->
            log "Seems something broken:", controller, err

        mine                :
          title             : "My groups"
          loggedInOnly      : yes
          dataSource        : (selector, options, callback)=>
            KD.whoami().fetchGroups (err, items)=>
              ids = []
              for item in items
                item.followee = true
                ids.push item.group.getId()
              callback err, (item.group for item in items)
              callback err, null, ids
          dataEnd           :({resultsController}, ids)=>
            {mine} = resultsController.listControllers
            @markGroupRelationship mine, ids

        pending             :
          title             : "Invited Groups"
          loggedInOnly      : yes
          dataSource        : (selector, options, callback)=>
            KD.whoami().fetchPendingGroupInvitations options, (err, groups)->
              callback err, groups
              callback err, null, (group.getId() for group in groups)
          dataEnd           :({resultsController}, ids)=>
            {pending} = resultsController.listControllers
            @markPendingGroupInvitations pending, ids

        requested             :
          title             : "Requested Groups"
          loggedInOnly      : yes
          dataSource        : (selector, options, callback)=>
            KD.whoami().fetchPendingGroupRequests options, (err, groups)->
              callback err, groups
              callback err, null, (group.getId() for group in groups)
          dataEnd           :({resultsController}, ids)=>
            {requested} = resultsController.listControllers
            @markPendingRequestGroups requested, ids

        # recommended         :
        #   title             : "Recommended"
        #   dataSource        : (selector, options, callback)=>
        #     callback 'Coming soon!'
      sort                  :
        'counts.members'    :
          title             : "Most popular"
          direction         : -1
        'meta.modifiedAt'   :
          title             : "Latest activity"
          direction         : -1
        'counts.posts'      :
          title             : "Most activity"
          direction         : -1
    }, (controller)=>
      view.addSubView @_lastSubview = controller.getView()
      @feedController = controller
      @feedController.resultsController.on 'ItemWasAdded', @bound 'monitorGroupItemOpenLink'
      @feedController.loadFeed() if loadFeed
      @emit 'ready'

  markGroupRelationship:(controller, ids)->
    return unless KD.isLoggedIn()

    fetchRoles =
      member: (view)-> view.markMemberGroup()
      admin : (view)-> view.markGroupAdmin()
      owner : (view)-> view.markOwnGroup()
    for as, callback of fetchRoles
      do (as, callback)->
        KD.remote.api.JGroup.fetchMyMemberships ids, as, (err, groups)->
          return error err if err
          controller.forEachItemByIndex groups, callback

    KD.whoami().fetchPendingGroupRequests groupIds:ids, (err, groups)=>
      @markPendingRequestGroups controller, (group.getId() for group in groups)

    KD.whoami().fetchPendingGroupInvitations groupIds:ids, (err, groups)=>
      @markPendingGroupInvitations controller, (group.getId() for group in groups)

  markPendingRequestGroups:(controller, ids)->
    controller.forEachItemByIndex ids, (view)-> view.markPendingRequest()
  
  markPendingGroupInvitations:(controller, ids)->
    controller.forEachItemByIndex ids, (view)-> view.markPendingInvitation()

  monitorGroupItemOpenLink:(item)->
    item.on 'PrivateGroupIsOpened', @bound 'openPrivateGroup'

  getErrorModalOptions =(err)->
    defaultOptions =
      buttons       :
        Cancel      :
          cssClass  : "modal-clean-red"
          callback  : (event)-> @getDelegate().destroy()
    customOptions = switch err.accessCode
      when ERROR_NO_POLICY
        {
          title     : 'Sorry, this group does not have a membership policy!'
          content   : """
                      <div class='modalformline'>
                        The administrators have not yet defined a membership
                        policy for this private group.  No one may join this
                        group until a membership policy has been defined.
                      </div>
                      """
        }
      when ERROR_UNKNOWN
        {
          title     : 'Sorry, an unknown error has occurred!'
          content   : """
                      <div class='modalformline'>
                        Please try again later.
                      </div>
                      """
        }
      when ERROR_POLICY
        {
          title     : 'This is a private group'
          content   :
            """
            <div class="modalformline">#{err.message}</div>
            """
        }

    if err.accessCode is ERROR_POLICY
      defaultOptions.buttons['Request access'] =
        cssClass    : 'modal-clean-green'
        loader      :
          color     : "#ffffff"
          diameter  : 12
        callback    : -> @getDelegate().emit 'AccessIsRequested'

    _.extend defaultOptions, customOptions

  removePaneByName:(tabView, paneName)->
    tabs = tabView.tabView
    invitePane = tabs.getPaneByName paneName
    tabs.removePane invitePane if invitePane

  showErrorModal:(group, err)->
    modal = new KDModalView getErrorModalOptions err
    modal.on 'AccessIsRequested', =>
      @getSingleton('staticGroupController')?.emit 'AccessIsRequested', group
      @requestAccess group, (err)-> modal.destroy()

  showRequestAccessModal:(group, policy, callback=->)->
    if policy.explanation?
      title = "Request Access"
      content = __utils.applyMarkdown policy.explanation
      success = "Your request has been sent to the group's admin."
    else if policy.approvalEnabled?
      title   = 'Request Access'
      content = 'Membership to this group requires administrative approval.'
      success = "Thanks! You'll be notified when group's admin accepts you."
    else
      title   = 'Request an Invite'
      content = 'Membership to this group requires an invitation.'
      success = "Your request has been sent to the group's admin."

    modal = new KDModalView
      title          : title
      overlay        : yes
      width          : 300
      height         : 'auto'
      content        : "<div class='modalformline'><p>#{content}</p></div>"
      buttons        :
        request      :
          title      : title
          loader     :
            color    : "#ffffff"
            diameter : 12
          style      : 'modal-clean-green'
          callback   : (event)->
            group.requestAccess (err)->
              modal.buttons.request.hideLoader()
              callback err
              new KDNotificationView title:
                if err then err.message else success
              modal.destroy() unless err

  joinGroup:(group)->
    group.join (err, response)=>
      if err
        error err
        new KDNotificationView
          title : "An error occured, please try again"
      else
        new KDNotificationView
          title : "You've successfully joined the group!"
        @getSingleton('mainController').emit 'JoinedGroup'

  acceptInvitation:(group, callback)->
    KD.whoami().acceptInvitation group, callback

  ignoreInvitation:(group, callback)->
    KD.whoami().ignoreInvitation group, callback
  
  cancelGroupRequest:(group, callback)->
    KD.whoami().cancelRequest group, callback

  openPrivateGroup:(group)->
    group.canOpenGroup (err, hasPermission)=>
      if err
        @showErrorModal group, err
      else if hasPermission
        @openGroup group

  _createGroupHandler =(formData, callback)->

    if formData.privacy in ['by-invite', 'by-request', 'same-domain']
      formData.privacy = 'private'

    KD.remote.api.JGroup.create formData, (err, group)=>
      if err
        callback? err
        new KDNotificationView
          title: err.message
          duration: 1000
      else
        callback no
        @showGroupCreatedModal group
        @createContentDisplay group

  _updateGroupHandler =(group, formData)->
    group.modify formData, (err)->
      if err
        new KDNotificationView
          title: err.message
          duration: 1000
      else
        new KDNotificationView
          title: 'Group was updated!'
          duration: 1000

  showGroupSubmissionView:->

    verifySlug = (slug)->

      queryDB = (s)->
        KD.remote.api.JName.one
          name : "#{s}"
        , (err,name)=>
          unless name
            modal.modalTabs.forms["General Settings"].inputs.Slug.setValue s
          else
            slug = name.name
            if '-' in slug
              parts = slug.split('-')
              suffix = parseInt parts[parts.length - 1]
              if not isNaN(suffix)
                parts[parts.length - 1] = suffix + 1
                slug = parts.join('-')
              else
                slug += '-1'
            else
              slug += '-1'
            queryDB slug

      modal.modalTabs.forms["General Settings"].inputs.Slug.setValue slug
      if slug.length > 0
        queryDB slug

    getGroupType = ->
      modal.modalTabs.forms["Select group type"].inputs.type.getValue()

    getPrivacyDefault = ->
      switch getGroupType()
        when 'educational'  then 'by-request'
        when 'company'      then 'by-invite'
        when 'project'      then'public'
        when 'custom'       then 'public'

    getVisibilityDefault = ->
      switch getGroupType()
        when 'educational'  then 'visible'
        when 'company'      then 'hidden'
        when 'project'      then 'visible'
        when 'custom'       then 'visible'

    applyDefaults =->
      {Privacy,Visibility} = modal.modalTabs.forms["General Settings"].inputs
      Privacy.setValue getPrivacyDefault()
      Visibility.setValue getVisibilityDefault()

    modalOptions =
      title                          : 'Create a new group'
      height                         : 'auto'
      cssClass                       : "group-admin-modal compose-message-modal admin-kdmodal"
      width                          : 500
      overlay                        : yes
      tabs                           :
        navigable                    : no
        goToNextFormOnSubmit         : yes
        hideHandleContainer          : yes
        callback                     :(formData)=>
          _createGroupHandler.call @, formData, (err) ->
            modal.modalTabs.forms["General Settings"].buttons.Save.hideLoader()
            unless err
              modal.destroy()
        forms                        :
          "Select group type"        :
            title                    : 'Group type'
            callback                 :(formData)=>
              log "here"
            buttons                  :
              "Next"                 :
                style                : "modal-clean-gray"
                type                 : "submit"
                callback             : -> applyDefaults()
            fields                   :
              "type"                 :
                name                 : "type"
                itemClass            : KDInputRadioGroup
                defaultValue         : "project"
                cssClass             : "group-type"
                radios               : [
                  { title : "University/School", value : "educational"}
                  { title : "Company",           value : "company"}
                  { title : "Project",           value : "project"}
                  { title : "Other",             value : "custom"}
                ]
          "General Settings"         :
            title                    : 'Create a group'
            buttons                  :
              "Save"                 :
                style                : "modal-clean-gray"
                type                 : "submit"
                loader               :
                  color              : "#444444"
                  diameter           : 12
              "Back"                 :
                style                : "modal-cancel"
                callback             : -> modal.modalTabs.showPreviousPane()
            fields                   :
              "Title"                :
                label                : "Title"
                name                 : "title"
                keydown              : (pubInst, event)->
                  @utils.defer =>
                    slug = @utils.slugify @getValue()
                    verifySlug slug


                placeholder          : 'Please enter your group title...'
              "Slug"                 :
                label                : "Slug"
                name                 : "slug"
                blur                 : ->
                  @utils.defer =>
                    slug = @utils.slugify @getValue()
                    verifySlug slug
                keydown              : ->
                  @utils.defer =>
                    slug = @utils.slugify @getValue()
                    verifySlug slug

                defaultValue         : ""
                placeholder          : 'This value will be automatically generated'
              "Description"          :
                label                : "Description"
                type                 : "textarea"
                name                 : "body"
                defaultValue         : ""
                placeholder          : "Please enter a description for your group here..."
              "Privacy"              :
                label                : "Privacy settings"
                itemClass            : KDSelectBox
                type                 : "select"
                name                 : "privacy"
                defaultValue         : "public"
                selectOptions        :
                  Public             : [
                    { title : "Anyone can join",    value : "public" }
                  ]
                  Private            : [
                    { title : "By invitation",       value : "by-invite" }
                    { title : "By access request",   value : "by-request" }
                    { title : "In same domain",      value : "same-domain" }
                  ]
              "Visibility"           :
                label                : "Visibility settings"
                itemClass            : KDSelectBox
                type                 : "select"
                name                 : "visibility"
                defaultValue         : "visible"
                selectOptions        : [
                  { title : "Visible in group listings",    value : "visible" }
                  { title : "Hidden in group listings",     value : "hidden" }
                ]
              # # Group VM should be there for every group
              #
              # "Group VM"             :
              #   label                : "Create a shared server for the group"
              #   itemClass            : KDOnOffSwitch
              #   name                 : "group-vm"
              #   defaultValue         : no
              #
              # # Members VMs are a future feature
              #
              # "Member VM"            :
              #   label                : "Create a server for each group member"
              #   itemClass            : KDOnOffSwitch
              #   name                 : "member-vm"
              #   defaultValue         : no

    modal = new KDModalViewWithForms modalOptions

  handleError =(err, buttons)->
    unless buttons
      new KDNotificationView title: err.message
    else

      modalOptions =
        title   : "Error#{if err.code then " #{code}" else ""}"
        content : "<div class='modalformline'><p>#{err.message}</p></div>"
        buttons : {}
        cancel  : err.cancel

      Object.keys(buttons).forEach (buttonTitle)->
        buttonOptions = buttons[buttonTitle]
        oldCallback = buttonOptions.callback
        buttonOptions.callback = -> oldCallback modal

        modalOptions.buttons[buttonTitle] = buttonOptions

      modal = new KDModalView modalOptions

  resolvePendingRequests:(group, takeDestructiveAction, callback, modal)->
    group.resolvePendingRequests takeDestructiveAction, (err)->
      modal.destroy()
      handleError err  if err?
      callback err

  cancelMembershipPolicyChange:(policy, membershipPolicyView, modal)->
    membershipPolicyView.enableInvitations.setValue policy.invitationsEnabled

  updateMembershipPolicy:(group, policy, formData, membershipPolicyView, callback)->
    group.modifyMembershipPolicy formData, ->
      membershipPolicyView.emit 'MembershipPolicyChangeSaved'

  editPermissions:(group)->
    group.getData().fetchPermissions (err, permissionSet)->
      if err
        new KDNotificationView title: err.message
      else
        permissionsModal = new PermissionsModal {
          privacy: group.getData().privacy
          permissionSet
        }, group

  loadView:(mainView, firstRun = yes, loadFeed = no)->

    if firstRun
      mainView.on "searchFilterChanged", (value) =>
        return if value is @_searchValue
        @_searchValue = Encoder.XSSEncode value
        @_lastSubview.destroy?()
        @loadView mainView, no, yes
      mainView.createCommons()

    @createFeed mainView, loadFeed

  openGroup:(group)->
    {slug, title} = group
    modal = new KDModalView
      title           : title
      content         : "<div class='modalformline'>You are about to open a third-party group.</div>"
      height          : "auto"
      overlay         : yes
      buttons         :
        cancel        :
          style       : 'modal-cancel'
          callback    : -> modal.destroy()
    modal.buttonHolder.addSubView new CustomLinkView
      href    : "/#{slug}/Activity"
      target  : slug
      title   : 'Open group'
      # click   : (event)->
      #   event.preventDefault()
      #   @getSingleton('windowManager').open @href, slug

  setCurrentViewHeader:(count)->
    if typeof 1 isnt typeof count
      @getView().$(".feeder-header span.optional_title").html count
      return no
    if count >= 20 then count = '20+'
    # return if count % 20 is 0 and count isnt 20
    # postfix = if count is 20 then '+' else ''
    count   = 'No' if count is 0
    result  = "#{count} result" + if count isnt 1 then 's' else ''
    title   = "#{result} found for <strong>#{@_searchValue}</strong>"
    @getView().$(".feeder-header").html title

  prepareReadmeTab:->
    {groupView} = this
    group = groupView.getData()
    groupView.tabView.addPane pane = new KDTabPaneView
      name: 'Readme'
    pane.addSubView new GroupReadmeView {}, group
    return pane

  prepareSettingsTab:->
    pane = @groupView.createLazyTab 'Settings', GroupGeneralSettingsView
    return pane

  preparePermissionsTab:->
    {groupView} = this
    pane = groupView.createLazyTab 'Permissions', GroupPermissionsView,
      delegate: groupView
    return pane

  prepareMembersTab:->
    {groupView} = this
    group = groupView.getData()
    pane = groupView.createLazyTab 'Members', GroupsMemberPermissionsView,
      (pane, view)=>
        pane.on 'PaneDidShow', ->
          view.refresh()  if pane.tabHandle.isDirty
          pane.tabHandle.markDirty no

    group.on 'MemberAdded', ->
      {tabHandle} = pane
      tabHandle.markDirty()
    return pane

  prepareMembershipPolicyTab:(group, view, groupView)->
    {groupView} = this
    group = groupView.getData()
    pane = groupView.createLazyTab 'Membership policy', GroupsMembershipPolicyView,
      (pane, view)=>

        group.fetchMembershipPolicy (err, policy)=>
          view.loader.hide()
          view.loaderText.hide()

          membershipPolicyView = new GroupsMembershipPolicyDetailView {}, policy

          membershipPolicyView.on 'MembershipPolicyChanged', (formData)=>
            @updateMembershipPolicy group, policy, formData, membershipPolicyView

          membershipPolicyView.on 'MembershipPolicyChangeSaved', => console.log 'sssaved'

          view.addSubView membershipPolicyView
    return pane

  prepareInvitationsTab:->
    {groupView} = this
    group = groupView.getData()
    pane = groupView.createLazyTab 'Invitations', GroupsInvitationRequestsView,
      (pane, invitationRequestView)->

        kallback = (modal, err)=>
          modal.modalTabs.forms.invite.buttons.Send.hideLoader()
          return invitationRequestView.showErrorMessage err if err
          new KDNotificationView title:'Invitation sent!'
          invitationRequestView.refresh()
          modal.destroy()

        invitationRequestView.on 'BatchApproveRequests', (formData)->
          group.sendSomeInvitations formData.count, (err)=>
            return invitationRequestView.showErrorMessage err if err
            invitationRequestView.prepareBulkInvitations()
            kallback @batchApprove, err

        invitationRequestView.on 'InviteByEmail', (formData)->
          group.inviteByEmails formData.emails, (err)=>
            kallback @inviteByEmail, err

        invitationRequestView.on 'InviteByUsername', (formData)->
          group.inviteByUsername formData.recipients, (err)=>
            kallback @inviteByUsername, err

        invitationRequestView.on 'RequestIsApproved', (request)->
          request.approveInvitation()

        invitationRequestView.on 'RequestIsDeclined', (request)->
          request.declineInvitation()

        pane.on 'PaneDidShow', ->
          invitationRequestView.refresh()  if pane.tabHandle.isDirty
          pane.tabHandle.markDirty no

    group.on 'NewInvitationRequest', ->
      pane.emit 'NewInvitationActionArrived'
      pane.tabHandle.markDirty()

    return pane

  prepareVocabularyTab:->
    {groupView} = this
    group = groupView.getData()
    pane = groupView.createLazyTab 'Vocabulary', GroupsVocabulariesView,
      (pane, vocabView)->

        group.fetchVocabulary (err, vocab)-> vocabView.setVocabulary vocab

        vocabView.on 'VocabularyCreateRequested', ->
          {JVocabulary} = KD.remote.api
          JVocabulary.create {}, (err, vocab)->
            vocabView.setVocabulary vocab

  createContentDisplay:(group, callback)->

    @groupView = groupView = new GroupView
      cssClass : "group-content-display"
      delegate : @getView()
    , group

    @prepareReadmeTab()
    @prepareSettingsTab()
    @preparePermissionsTab()
    @prepareMembersTab()
#    @prepareVocabularyTab()

    if 'private' is group.privacy
      @prepareMembershipPolicyTab()
      @prepareInvitationsTab()

    contentDisplay = @showContentDisplay @groupView
    callback? contentDisplay


  showContentDisplay:(groupView)->
    contentDisplayController = @getSingleton "contentDisplayController"
    contentDisplayController.emit "ContentDisplayWantsToBeShown", groupView
    groupView.on 'PrivateGroupIsOpened', @bound 'openPrivateGroup'
    return groupView

  loginRequired:(callback)->
    new KDNotificationView
      type     : 'mini'
      cssClass : 'error'
      title    : 'Login is required for this action'
      duration : 5000

    {entryPoint} = KD.config

    @getSingleton('router').handleRoute "/Login", {entryPoint}
    @getSingleton('mainController').once 'AccountChanged', ->
      if KD.isLoggedIn()
        callback()

  showGroupCreatedModal:(group)->
    group.fetchMembershipPolicy (err, policy)=>
      return new KDNotificationView title: 'An error occured, however your group has been created!' if err

      port = if location.port isnt 80 then ":#{location.port}" else ''
      groupUrl = "#{location.protocol}//#{location.hostname}#{port}/#{group.slug}"

      if group.privacy is 'public'
        privacyExpl = 'Koding users can join anytime without approval'
      else if policy.invitationsEnabled
        privacyExpl = 'and only invited users can join'
      else
        privacyExpl = 'Koding users can only join with your approval'

      body  = """
        <div class="modalformline">Your group can be accessed via <a class="group-link" href="#{groupUrl}">#{groupUrl}</a></div>
        <div class="modalformline">It is <strong>#{group.visibility}</strong> in group listings.</div>
        <div class="modalformline">It is <strong>#{group.privacy}</strong>, #{privacyExpl}.</div>
        <div class="modalformline">You can manage your group settings from the group dashboard anytime.</div>
        """
      modal = new KDModalView
        title        : "#{group.title} has been created!"
        content      : body
        click        : (event)->
          if $(event.target).is 'a.group-link' then modal.destroy()
        buttons      :
          dashboard  :
            title    : 'Go to Dashboard'
            style    : 'modal-clean-green'
            callback : -> modal.destroy()
          group      :
            title    : 'Go to Group'
            style    : 'modal-clean-gray'
            callback : =>
              modal.destroy()
              KD.getSingleton('router').handleRoute "/#{group.slug}"
          dismiss    :
            title    : 'Dismiss'
            style    : 'modal-cancel'
            callback : -> modal.destroy()

  # old load view
  # loadView:(mainView, firstRun = yes)->

  #   if firstRun
  #     mainView.on "searchFilterChanged", (value) =>
  #       return if value is @_searchValue
  #       @_searchValue = Encoder.XSSEncode value
  #       @_lastSubview.destroy?()
  #       @loadView mainView, no

  #     mainView.createCommons()

  #   KD.whoami().fetchRole? (err, role) =>
  #     if role is "super-admin"
  #       @listItemClass = GroupsListItemViewEditable
  #       if firstRun
  #         @getSingleton('mainController').on "EditPermissionsButtonClicked", (groupItem)=>
  #           @editPermissions groupItem
  #         @getSingleton('mainController').on "EditGroupButtonClicked", (groupItem)=>
  #           groupData = groupItem.getData()
  #           groupData.canEditGroup (err, hasPermission)=>
  #             unless hasPermission
  #               new KDNotificationView title: 'Access denied'
  #             else
  #               @showGroupSubmissionView groupData
  #         @getSingleton('mainController').on "MyRolesRequested", (groupItem)=>
  #           groupItem.getData().fetchRoles console.log.bind console

  #     @createFeed mainView
  #   # mainView.on "AddATopicFormSubmitted",(formData)=> @addATopic formData
