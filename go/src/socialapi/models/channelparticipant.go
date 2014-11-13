package models

import (
	"fmt"
	"socialapi/request"
	"time"

	"github.com/jinzhu/gorm"
	"github.com/koding/bongo"
)

// todo Scope function for this struct
// in order not to fetch passive accounts
type ChannelParticipant struct {
	// unique identifier of the channel
	Id int64 `json:"id,string"`

	// Id of the channel
	ChannelId int64 `json:"channelId,string"       sql:"NOT NULL"`

	// Id of the account
	AccountId int64 `json:"accountId,string"       sql:"NOT NULL"`

	// Status of the participant in the channel
	StatusConstant string `json:"statusConstant"   sql:"NOT NULL;TYPE:VARCHAR(100);"`

	// Role of the participant in the channel
	RoleConstant string `json:"roleConstant"`

	// holds troll, unsafe, etc
	MetaBits MetaBits `json:"metaBits"`

	// date of the user's last access to regarding channel
	LastSeenAt time.Time `json:"lastSeenAt"        sql:"NOT NULL"`

	// Creation date of the channel channel participant
	CreatedAt time.Time `json:"createdAt"          sql:"NOT NULL"`

	// Modification date of the channel participant's status
	UpdatedAt time.Time `json:"updatedAt"          sql:"NOT NULL"`
}

// here is why i did this not-so-good constants
// https://code.google.com/p/go/issues/detail?id=359
const (
	ChannelParticipant_STATUS_ACTIVE              = "active"
	ChannelParticipant_STATUS_LEFT                = "left"
	ChannelParticipant_STATUS_REQUEST_PENDING     = "requestpending"
	ChannelParticipant_Added_To_Channel_Event     = "added_to_channel"
	ChannelParticipant_Removed_From_Channel_Event = "removed_from_channel"
)

func NewChannelParticipant() *ChannelParticipant {
	return &ChannelParticipant{
		StatusConstant: ChannelParticipant_STATUS_ACTIVE,
		RoleConstant:   Permission_ROLE_MEMBER,
		LastSeenAt:     time.Now().UTC(),
		CreatedAt:      time.Now().UTC(),
		UpdatedAt:      time.Now().UTC(),
	}
}

// Create creates a participant in the db as active
// multiple call of this function will result
func (c *ChannelParticipant) Create() error {
	err := c.FetchParticipant()
	if err != nil && err != bongo.RecordNotFound {
		return err
	}

	// if err is nil
	// it means we already have that user in the channel
	if err == nil {
		// if the participant is already in the channel, and active do nothing
		if c.StatusConstant == ChannelParticipant_STATUS_ACTIVE {
			return nil
		}

		c.StatusConstant = ChannelParticipant_STATUS_ACTIVE
		if err := c.Update(); err != nil {
			return err
		}

	} else {
		if err := bongo.B.Create(c); err != nil {
			return err
		}
	}

	return nil
}

func (c *ChannelParticipant) CreateRaw() error {
	insertSql := "INSERT INTO " +
		c.BongoName() +
		` ("channel_id","account_id", "status_constant", "last_seen_at","created_at", "updated_at") ` +
		"VALUES ($1,$2,$3,$4,$5,$6) " +
		"RETURNING ID"

	return bongo.B.DB.CommonDB().
		QueryRow(insertSql, c.ChannelId, c.AccountId, c.StatusConstant, c.LastSeenAt, c.CreatedAt, c.UpdatedAt).
		Scan(&c.Id)
}

// Tests are done.
func (c *ChannelParticipant) FetchParticipant() error {
	if c.ChannelId == 0 {
		return ErrChannelIdIsNotSet
	}

	if c.AccountId == 0 {
		return ErrAccountIdIsNotSet
	}

	selector := map[string]interface{}{
		"channel_id": c.ChannelId,
		"account_id": c.AccountId,
	}

	return c.fetchParticipant(selector)
}

// Tests are done.
func (c *ChannelParticipant) FetchActiveParticipant() error {
	selector := map[string]interface{}{
		"channel_id":      c.ChannelId,
		"account_id":      c.AccountId,
		"status_constant": ChannelParticipant_STATUS_ACTIVE,
	}

	return c.fetchParticipant(selector)
}

func (c *ChannelParticipant) fetchParticipant(selector map[string]interface{}) error {
	if c.ChannelId == 0 {
		return ErrChannelIdIsNotSet
	}

	if c.AccountId == 0 {
		return ErrAccountIdIsNotSet
	}

	// TODO do we need to add isExempt scope here?
	err := c.One(bongo.NewQS(selector))
	if err != nil {
		return err
	}

	return nil
}

// Tests are done in channelmessagelist.
func (c *ChannelParticipant) FetchUnreadCount() (int, error) {
	cml := NewChannelMessageList()
	return cml.UnreadCount(c)
}

func (c *ChannelParticipant) Delete() error {
	if err := c.FetchParticipant(); err != nil {
		return err
	}

	c.StatusConstant = ChannelParticipant_STATUS_LEFT
	if err := c.Update(); err != nil {
		return err
	}

	return nil
}

func (c *ChannelParticipant) List(q *request.Query) ([]ChannelParticipant, error) {
	var participants []ChannelParticipant

	if c.ChannelId == 0 {
		return participants, ErrChannelIdIsNotSet
	}

	query := &bongo.Query{
		Selector: map[string]interface{}{
			"channel_id":      c.ChannelId,
			"status_constant": ChannelParticipant_STATUS_ACTIVE,
		},
	}

	// add filter for troll content
	query.AddScope(RemoveTrollContent(c, q.ShowExempt))

	err := bongo.B.Some(c, &participants, query)
	if err != nil {
		return nil, err
	}

	return participants, nil
}

func (c *ChannelParticipant) ListAccountIds(limit int) ([]int64, error) {
	var participants []int64

	if c.ChannelId == 0 {
		return participants, ErrChannelIdIsNotSet
	}

	query := &bongo.Query{
		Selector: map[string]interface{}{
			"channel_id":      c.ChannelId,
			"status_constant": ChannelParticipant_STATUS_ACTIVE,
		},
		Pluck: "account_id",
	}

	if limit != 0 {
		query.Pagination = *bongo.NewPagination(limit, 0)
	}

	// do not include troll content
	query.AddScope(RemoveTrollContent(c, false))

	err := bongo.B.Some(c, &participants, query)
	if err != nil {
		return nil, err
	}

	return participants, nil
}

func getParticipatedChannelsQuery(a *Account, q *request.Query) *gorm.DB {
	c := NewChannelParticipant()

	return bongo.B.DB.
		Model(c).
		Table(c.BongoName()).
		Select("api.channel_participant.channel_id").
		Joins(
		`left join api.channel on
		 api.channel_participant.channel_id = api.channel.id`).
		Where(
		`api.channel_participant.account_id = ? and
		 api.channel.group_name = ? and
		 api.channel.type_constant = ? and
		 api.channel_participant.status_constant = ?`,
		a.Id,
		q.GroupName,
		q.Type,
		ChannelParticipant_STATUS_ACTIVE,
	)
}

func (c *ChannelParticipant) ParticipatedChannelCount(a *Account, q *request.Query) (*CountResponse, error) {
	if a.Id == 0 {
		return nil, ErrAccountIdIsNotSet
	}

	query := getParticipatedChannelsQuery(a, q)

	// add exempt clause if needed
	if !q.ShowExempt {
		query = query.Where("api.channel.meta_bits = ?", Safe)
	}

	var count int
	query = query.Count(&count)
	if query.Error != nil {
		return nil, query.Error
	}

	res := new(CountResponse)
	res.TotalCount = count

	return res, nil
}

func (c *ChannelParticipant) FetchParticipatedChannelIds(a *Account, q *request.Query) ([]int64, error) {
	if a.Id == 0 {
		return nil, ErrAccountIdIsNotSet
	}

	channelIds := make([]int64, 0)

	// var results []ChannelParticipant
	query := getParticipatedChannelsQuery(a, q)

	// add exempt clause if needed
	if !q.ShowExempt {
		query = query.Where("api.channel.meta_bits = ?", Safe)
	}

	rows, err := query.
		Limit(q.Limit).
		Offset(q.Skip).
		Rows()

	defer rows.Close()
	if err != nil {
		return channelIds, err
	}

	if rows == nil {
		return nil, nil
	}

	var channelId int64
	for rows.Next() {
		rows.Scan(&channelId)
		channelIds = append(channelIds, channelId)
	}

	// if this is the first query for listing the channels
	// add default channels into the result set
	if q.Skip == 0 {
		defaultChannels, err := c.fetchDefaultChannels(q)
		if err != nil {
			fmt.Println(err.Error())
		} else {
			for _, item := range channelIds {
				defaultChannels = append(defaultChannels, item)
			}
			return defaultChannels, nil
		}
	}

	return channelIds, nil
}

// fetchDefaultChannels fetchs the default channels of the system, currently we
// have two different default channels, group channel and announcement channel
// that everyone in the system should be a member of them, they cannot opt-out,
// they will be able to see the contents of it, they will get the notifications,
// they will see the unread count
func (c *ChannelParticipant) fetchDefaultChannels(q *request.Query) ([]int64, error) {
	var channelIds []int64
	channel := NewChannel()
	res := bongo.B.DB.
		Model(channel).
		Table(channel.BongoName()).
		Where(
		"group_name = ? AND type_constant IN (?)",
		q.GroupName,
		[]string{Channel_TYPE_GROUP, Channel_TYPE_ANNOUNCEMENT},
	).
		// no need to traverse all database, limit with a known count
		Limit(2).
		// only select ids
		Pluck("id", &channelIds)

	if err := bongo.CheckErr(res); err != nil {
		return nil, err
	}

	// be sure that this account is a participant of default channels
	if err := c.ensureParticipation(q.AccountId, channelIds); err != nil {
		return nil, err
	}

	return channelIds, nil
}

func (c *ChannelParticipant) ensureParticipation(accountId int64, channelIds []int64) error {
	for _, channelId := range channelIds {
		cp := NewChannelParticipant()
		cp.ChannelId = channelId
		cp.AccountId = accountId
		// create is idempotent, multiple calls wont cause any problem, if the
		// user is already a participant, will return as if a succesful request
		if err := cp.Create(); err != nil {
			return err
		}
	}

	return nil
}

// FetchParticipantCount fetchs the participant count in the channel
// if there is no participant in the channel, then returns zero value
//
// Tests are done.
func (c *ChannelParticipant) FetchParticipantCount() (int, error) {
	if c.ChannelId == 0 {
		return 0, ErrChannelIdIsNotSet
	}

	return c.Count("channel_id = ? and status_constant = ?", c.ChannelId, ChannelParticipant_STATUS_ACTIVE)
}

// Tests are done.
func (c *ChannelParticipant) IsParticipant(accountId int64) (bool, error) {
	if c.ChannelId == 0 {
		return false, ErrChannelIdIsNotSet
	}

	selector := map[string]interface{}{
		"channel_id":      c.ChannelId,
		"account_id":      accountId,
		"status_constant": ChannelParticipant_STATUS_ACTIVE,
	}

	err := c.One(bongo.NewQS(selector))
	if err == nil {
		return true, nil
	}

	if err == bongo.RecordNotFound {
		return false, nil
	}

	return false, err
}

// Put them all behind an interface
// channels, messages, lists, participants, etc
//
// Tests are done.
func (c *ChannelParticipant) MarkIfExempt() error {
	isExempt, err := c.isExempt()
	if err != nil {
		return err
	}

	if isExempt {
		c.MetaBits.Mark(Troll)
	}

	return nil
}

// Tests are done.
func (c *ChannelParticipant) isExempt() (bool, error) {
	// return early if channel is already exempt
	if c.MetaBits.Is(Troll) {
		return true, nil
	}

	accountId, err := c.getAccountId()
	if err != nil {
		return false, err
	}

	account, err := ResetAccountCache(accountId)
	if err != nil {
		return false, err
	}

	if account == nil {
		return false, fmt.Errorf("account is nil, accountId:%d", accountId)
	}

	if account.IsTroll {
		return true, nil
	}

	return false, nil
}

// Tests are done.
func (c *ChannelParticipant) getAccountId() (int64, error) {
	if c.AccountId != 0 {
		return c.AccountId, nil
	}

	if c.Id == 0 {
		return 0, fmt.Errorf("couldnt find accountId from content %+v", c)
	}

	cp := NewChannelParticipant()
	if err := cp.ById(c.Id); err != nil {
		return 0, err
	}

	return cp.AccountId, nil
}

func (c *ChannelParticipant) RawUpdateLastSeenAt(t time.Time) error {
	if c.Id == 0 {
		return ErrIdIsNotSet
	}

	query := fmt.Sprintf("UPDATE %s SET last_seen_at = ? WHERE id = ?", c.BongoName())
	return bongo.B.DB.Exec(query, t, c.Id).Error
}

func (c *ChannelParticipant) FetchRole() (string, error) {
	// mark guests as guest
	if c.AccountId == 0 {
		return Permission_ROLE_GUEST, nil
	}

	// fetch participant
	err := c.FetchParticipant()
	if err != nil && err != bongo.RecordNotFound {
		return "", err
	}

	// if not a member, mark as guest
	if err == bongo.RecordNotFound {
		return Permission_ROLE_GUEST, nil
	}

	if c.RoleConstant == "" {
		return Permission_ROLE_GUEST, nil
	}

	return c.RoleConstant, nil
}
